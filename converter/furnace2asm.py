import sys
import os

def parse_note(s):
    if s == '...' or s == '..': return None
    if s in ('OFF', '===', 'REL'):
        return 0x00 if s == 'OFF' else 0x01
    
    # Notes mapping (A-0 starts at 0x02)
    notes = {'C-': 0, 'C#': 1, 'D-': 2, 'D#': 3, 'E-': 4, 'F-': 5, 'F#': 6, 'G-': 7, 'G#': 8, 'A-': 9, 'A#': 10, 'B-': 11}
    n = s[:2]
    try:
        octave = int(s[2])
        # A-0 is index 9 of octave 0 in typical mapping? 
        # C-0=0, A-0=9. -> 9 - 9 + 2 = 2.
        val = octave * 12 + notes[n] - 9 + 2
        return max(0x02, min(0x7F, val))
    except:
        return None

def parse_cell(cell_str):
    tokens = cell_str.strip().split()
    note_str = tokens[0] if len(tokens) > 0 else '...'
    inst_str = tokens[1] if len(tokens) > 1 else '..'
    vol_str = tokens[2] if len(tokens) > 2 else '..'
    fx_strs = tokens[3:] if len(tokens) > 3 else []
    
    note = parse_note(note_str)
    
    fx_list = []
    if inst_str != '..': fx_list.append(('INST', int(inst_str, 16)))
    if vol_str != '..': fx_list.append(('VOL', int(vol_str, 16)))
    for fx in fx_strs:
        if fx != '....':
            etype = fx[:2]
            eval_ = int(fx[2:], 16)
            if etype == '04': fx_list.append(('FX_82', eval_))
            # 추가할 이펙트가 있으면 여기에 계속 추가하시면 됩니다.
            
    return note, fx_list

def is_cell_empty(note, fx_list):
    return note is None and len(fx_list) == 0

def encode_fx(fx, is_last):
    base = 0xA0 if is_last else 0x80
    if fx[0] == 'INST': return [base | 0x00, fx[1]]
    elif fx[0] == 'VOL': return [base | 0x01, fx[1]]
    elif fx[0] == 'FX_82': return [base | 0x02, fx[1]]
    return []

def emit_row(note, fx_list):
    out = []
    if note is not None:
        out.append(note)
        
    len_fx = next((f for f in fx_list if f[0] == 'LEN'), None)
    norm_fx = [f for f in fx_list if f[0] != 'LEN']
    
    if len_fx:
        # LEN 이펙트가 있으면 무조건 ROW 파싱 중단이 보장되므로 이전 이펙트들은 $80~$9F 베이스 사용
        for f in norm_fx:
            out.extend(encode_fx(f, is_last=False))
        out.append(0xC0 + len_fx[1] - 1)
    else:
        # LEN 이펙트가 없을 때
        if len(norm_fx) > 0:
            for i, f in enumerate(norm_fx):
                is_last = (i == len(norm_fx) - 1)
                out.extend(encode_fx(f, is_last=is_last))
        else:
            # 이펙트가 하나도 없으면 note만 기록됨 (드라이버가 암시적으로 처리)
            pass
    return out

def to_byte_str(byte_list):
    if not byte_list: return ""
    return ".BYTE " + ", ".join(f"${b:02X}" for b in byte_list)

def generate_channel_data(cells_for_all_rows):
    N = len(cells_for_all_rows)
    bytes_out = []
    current_length = -1
    
    i = 0
    while i < N:
        # 1. 다음으로 데이터가 있는 ROW 찾기
        next_ne = i
        while next_ne < N and is_cell_empty(*cells_for_all_rows[next_ne]):
            next_ne += 1
            
        # 2. 빈 공간 (Gap)이 있다면 Length 커맨드로 대기
        gap = next_ne - i
        while gap > 0:
            chunk = min(gap, 64)
            if chunk != current_length:
                bytes_out.extend(emit_row(None, [('LEN', chunk)]))
                current_length = chunk
            else:
                bytes_out.extend(emit_row(None, [('LEN', chunk)]))
            gap -= chunk
            
        if next_ne == N:
            break
            
        note, fx_list = cells_for_all_rows[next_ne]
        
        # 3. 현재 유효한 ROW 이후로 다음 유효 ROW까지의 거리(Distance) 계산
        dist = 1
        for j in range(next_ne + 1, N):
            if not is_cell_empty(*cells_for_all_rows[j]):
                break
            dist += 1
            
        # 4. 거리가 64를 넘어가면 쪼개서 Length 커맨드 삽입
        while dist > 64:
            if 64 != current_length:
                fx_list.append(('LEN', 64))
                current_length = 64
            bytes_out.extend(emit_row(note, fx_list))
            dist -= 64
            note = None
            fx_list = [('LEN', min(dist, 64))]
            current_length = min(dist, 64)
            
        if dist != current_length:
            fx_list.append(('LEN', dist))
            current_length = dist
            
        bytes_out.extend(emit_row(note, fx_list))
        i = next_ne + dist
        
    return bytes_out

def convert_furnace(input_path):
    with open(input_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    base_name = os.path.splitext(os.path.basename(input_path))[0]
    
    instruments = []
    songs = []
    
    idx = 0
    
    # ---------------------------------------------------------
    # PHASE 1: 헤더 및 악기 파싱
    # ---------------------------------------------------------
    while idx < len(lines):
        line = lines[idx].strip()
        if '# Subsongs' in line:
            break
        
        if '- type: 1' in line:
            # FM 악기
            alg = fb = fms = ams = 0
            ops = [{} for _ in range(4)]
            while idx < len(lines):
                idx += 1
                l = lines[idx].strip()
                if l.startswith('- type:') or l.startswith('## ') or '# Subsongs' in l:
                    idx -= 1; break
                
                if l.startswith('- ALG:'): alg = int(l.split(':')[1].strip())
                elif l.startswith('- FB:'): fb = int(l.split(':')[1].strip())
                elif l.startswith('- FMS:'): fms = int(l.split(':')[1].strip())
                elif l.startswith('- AMS:'): ams = int(l.split(':')[1].strip())
                elif l.startswith('- operator '):
                    op_idx = int(l.split('operator ')[1].replace(':','').strip())
                    while idx + 1 < len(lines) and lines[idx+1].startswith('    - '):
                        idx += 1
                        pl = lines[idx].strip()
                        key = pl.split(':')[0].replace('- ', '').strip()
                        val = pl.split(':')[1].strip()
                        ops[op_idx][key] = int(val) if val.isdigit() or (val.startswith('-') and val[1:].isdigit()) else val
            
            inst_bytes = []
            inst_bytes.append(alg | (fb << 3))
            inst_bytes.append(fms | (ams << 4))
            for op in ops:
                b1 = (op.get('DT', 0) << 4) | op.get('MULT', 0)
                b2 = op.get('TL', 0)
                b3 = (op.get('RS', 0) << 6) | op.get('AR', 0)
                b4 = (op.get('AM', 0) << 7) | op.get('DR', 0)
                b5 = op.get('D2R', 0)
                b6 = (op.get('SL', 0) << 4) | op.get('RR', 0)
                b7 = op.get('SSG-EG', 0)
                inst_bytes.append([b1, b2, b3, b4, b5, b6, b7])
            instruments.append({'type': 1, 'data': inst_bytes})
            
        elif '- type: 6' in line:
            # SSG 악기
            vol_macro = [15, 0xFF]
            while idx < len(lines):
                idx += 1
                l = lines[idx].strip()
                if l.startswith('- type:') or l.startswith('## ') or '# Subsongs' in l:
                    idx -= 1; break
                    
                if l.startswith('- vol:'):
                    parts = l.replace('- vol:', '').strip().split()
                    macro = []
                    for p in parts:
                        if p == '/': macro.append(0x80)
                        else: macro.append(int(p))
                    macro.append(0xFF)
                    vol_macro = macro
            instruments.append({'type': 6, 'data': vol_macro})
        idx += 1

    # ---------------------------------------------------------
    # PHASE 2: 곡 및 패턴 파싱
    # ---------------------------------------------------------
    current_song = None
    while idx < len(lines):
        line = lines[idx].strip()
        if line.startswith('- tick rate:'):
            current_song = {'speeds': [], 'patlen': 0, 'orders': [], 'patterns': {}}
            songs.append(current_song)
        elif line.startswith('- speeds:') and current_song is not None:
            parts = line.replace('- speeds:', '').strip().split()
            current_song['speeds'] = [int(p) for p in parts]
        elif line.startswith('- pattern length:') and current_song is not None:
            current_song['patlen'] = int(line.split(':')[1].strip())
        elif line == 'orders:' and current_song is not None:
            idx += 1
            while idx < len(lines):
                l = lines[idx].strip()
                if not l or l.startswith('## '): 
                    idx -= 1; break
                if '|' in l:
                    parts = l.split('|')[1].strip().split()
                    current_song['orders'].append(parts)
                idx += 1
        elif line.startswith('----- ORDER '):
            order_id = line.replace('----- ORDER ', '').strip()
            rows = []
            idx += 1
            while idx < len(lines) and '|' in lines[idx]:
                row_str = lines[idx].split('|')[1:-1]
                rows.append(row_str)
                idx += 1
            idx -= 1
            current_song['patterns'][order_id] = rows
        idx += 1

    # ---------------------------------------------------------
    # PHASE 3: 헤더 .asm 파일 쓰기
    # ---------------------------------------------------------
    header_filename = f"{base_name}_header.asm"
    with open(header_filename, 'w') as f:
        f.write("furEPSM_header:\n")
        for i in range(len(songs)):
            f.write(f"    .WORD furEPSM_song{i:02d}\n")
        
        f.write("\nfurEPSM_instptr:\n")
        for i in range(len(instruments)):
            f.write(f"    .WORD furEPSM_inst{i:02X}\n")
            
        f.write("\n")
        for i, inst in enumerate(instruments):
            f.write(f"furEPSM_inst{i:02X}:\n")
            if inst['type'] == 1:
                # FM
                f.write("    " + to_byte_str([inst['data'][0], inst['data'][1]]) + "\n")
                for op in inst['data'][2:]:
                    f.write("    " + to_byte_str(op) + "\n")
            elif inst['type'] == 6:
                # SSG
                f.write("    " + to_byte_str(inst['data']) + "\n")
            f.write("\n")
    print(f"Generated {header_filename}")

    # ---------------------------------------------------------
    # PHASE 4: 곡별 .asm 파일 쓰기
    # ---------------------------------------------------------
    for i, song in enumerate(songs):
        song_filename = f"{base_name}_song{i:02d}.asm"
        with open(song_filename, 'w') as f:
            f.write(f"furEPSM_song{i:02d}:\n")
            f.write("    .WORD @frames\n")
            f.write(f"    .BYTE {len(song['orders'])} ; 프레임 개수\n")
            f.write(f"    .BYTE {song['patlen']} ; 패턴 길이\n")
            groove = song['speeds'] + [0xFF]
            f.write("    " + to_byte_str(groove) + " ; groove\n\n")
            
            f.write("@frames:\n")
            for frm_idx in range(len(song['orders'])):
                f.write(f"    .WORD @frame{frm_idx}\n")
            f.write("\n")
            
            for frm_idx, order in enumerate(song['orders']):
                f.write(f"@frame{frm_idx}:\n")
                ptr_strs = []
                for ch in range(6): ptr_strs.append(f"@fm{ch+1}pat{order[ch]}")
                for ch in range(3): ptr_strs.append(f"@ssg{ch+1}pat{order[6+ch]}")
                ptr_strs.append(f"@rhythmpat{order[9]}") # KICK 채널의 ID 사용
                f.write("    .WORD " + ", ".join(ptr_strs) + "\n\n")
                
            # 패턴 데이터 생성
            for pat_id, rows in song['patterns'].items():
                # FM 1~6 (0~5)
                for ch in range(6):
                    f.write(f"@fm{ch+1}pat{pat_id}:\n")
                    ch_cells = [parse_cell(r[ch]) for r in rows]
                    b_out = generate_channel_data(ch_cells)
                    f.write("    " + to_byte_str(b_out) + "\n")
                
                # SSG 1~3 (6~8)
                for ch in range(3):
                    f.write(f"@ssg{ch+1}pat{pat_id}:\n")
                    ch_cells = [parse_cell(r[6+ch]) for r in rows]
                    b_out = generate_channel_data(ch_cells)
                    f.write("    " + to_byte_str(b_out) + "\n")
                
                # 리듬 (9~14 합치기)
                f.write(f"@rhythmpat{pat_id}:\n")
                rhythm_cells = []
                for r in rows:
                    bitmask = 0
                    combined_fx = []
                    for rc_idx in range(6):
                        note, fx = parse_cell(r[9+rc_idx])
                        if note is not None and note >= 0x02:
                            bitmask |= (1 << rc_idx)
                        for efx in fx:
                            if not any(cf[0] == efx[0] for cf in combined_fx):
                                combined_fx.append(efx)
                    
                    r_note = bitmask if bitmask > 0 else None
                    rhythm_cells.append((r_note, combined_fx))
                    
                b_out = generate_channel_data(rhythm_cells)
                f.write("    " + to_byte_str(b_out) + "\n\n")

        print(f"Generated {song_filename}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python furnace2asm.py <input.txt>")
    else:
        convert_furnace(sys.argv[1])