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
            eval_ = int(fx[2:], 16) if fx[2:] != '..' else int('0',16)
            if etype == '04': fx_list.append(('eff_vibrato', eval_))
            if etype == '0D': fx_list.append(('eff_nextframe', eval_))
            if etype == '0B': fx_list.append(('eff_nextframe', eval_))
            if etype == 'FF': fx_list.append(('eff_end', eval_))
            if etype == '0F': fx_list.append(('eff_speed', eval_))
            if etype == 'FD': fx_list.append(('eff_tempo', eval_))
            if etype == 'ED': fx_list.append(('eff_rowdelay', eval_))
            if etype == 'E5': fx_list.append(('eff_pitchoffset', eval_))
            
    return note, fx_list

def is_cell_empty(note, fx_list):
    return note is None and len(fx_list) == 0

def encode_fx(fx, is_last):
    base = 0xA0 if is_last else 0x80
    if fx[0] == 'INST':
        inst_val = fx[1]
        # Quick Instrument Change (0~31) - Non-Terminating
        if not is_last and 0 <= inst_val <= 31:
            return [0xC0 + inst_val]
        # Otherwise, standard 2-byte command
        return [base | 0x00, inst_val]
    elif fx[0] == 'VOL':                return [base | 0x01, fx[1]] if fx[1] != 0x7F else [base | 0x02]
    elif fx[0] == 'eff_vibrato':        return [base | 0x03, fx[1]]
    elif fx[0] == 'eff_nextframe':      return [base | 0x04]
    elif fx[0] == 'eff_jumpframe':      return [base | 0x05, fx[1]]
    elif fx[0] == 'eff_end':            return [base | 0x06]
    elif fx[0] == 'eff_set_delay':      return [base | 0x07, fx[1] & 0xFF]
    elif fx[0] == 'eff_speed':          return [base | 0x08, fx[1]]
    elif fx[0] == 'eff_tempo':          return [base | 0x09, fx[1]]
    elif fx[0] == 'eff_rowdelay':       return [base | 0x0A, fx[1]]
    elif fx[0] == 'eff_pitchoffset':    return [base | 0x0B, fx[1]]
    return []

def emit_row(note, fx_list):
    out = []
    
    # 커맨드들을 종류별로 분류하여 우선순위에 따라 큐에 배치합니다.
    len_fx = next((f for f in fx_list if f[0] == 'LEN'), None)
    rowdelay_fx = next((f for f in fx_list if f[0] == 'eff_rowdelay'), None)
    other_fx = [f for f in fx_list if f[0] not in ('LEN', 'eff_rowdelay')]
    
    # 오직 딜레이(빈 공간)만을 위해 존재하는 열인지 확인
    use_standalone_delay = (note is None) and (len_fx is not None) and (len(other_fx) == 0) and (rowdelay_fx is None)

    # 1. 딜레이(LEN) 커맨드 처리 (항상 맨 먼저)
    if len_fx:
        if use_standalone_delay:
            # 독립 딜레이 커맨드: $E0~$FE (1~31), $FF (256)
            chunk_val = len_fx[1]
            if chunk_val == 256:
                out.append(0xFF)
            else:
                out.append(0xE0 + chunk_val - 1)
            return out  # 이것만 있으면 바로 종료
        else:
            # 노트나 다른 이펙트가 뒤따라올 예정이므로 논-터미네이팅 딜레이($87)로 제일 먼저 삽입
            out.extend(encode_fx(('eff_set_delay', len_fx[1]), is_last=False))

    # 2. Row Delay 커맨드 삽입 (딜레이 설정 직후)
    if rowdelay_fx:
        # 이 커맨드가 읽히면 드라이버가 파싱을 멈추고 틱을 넘길 것입니다.
        # 뒤에 다른 이펙트나 노트가 남았다면 논터미네이팅 플래그($8A)가 부여되어 자연스럽습니다.
        is_last = (len(other_fx) == 0) and (note is None)
        out.extend(encode_fx(rowdelay_fx, is_last=is_last))

    # 3. 일반 이펙트 처리 (Row Delay에 의해 파싱이 중단되었다면, 지연된 후에 읽히게 됩니다)
    if len(other_fx) > 0:
        for i, f in enumerate(other_fx):
            is_last = (i == len(other_fx) - 1) and (note is None)
            out.extend(encode_fx(f, is_last=is_last))
            
    # 4. 노트 삽입 (항상 맨 마지막에 위치하여 최종 종료자 역할 수행)
    if note is not None:
        out.append(note)
        
    return out

def to_byte_str(byte_list):
    if not byte_list: return ""
    return ".BYTE " + ", ".join(f"${b:02X}" for b in byte_list)

def generate_channel_data(cells_for_all_rows, is_rhythm=False):
    N = len(cells_for_all_rows)
    
    if not is_rhythm:
        current_inst = -1
        for i in range(N):
            note, fx_list = cells_for_all_rows[i]
            new_fx = []
            for fx in fx_list:
                if fx[0] == 'INST':
                    if fx[1] != current_inst:
                        new_fx.append(fx)
                        current_inst = fx[1]
                else:
                    new_fx.append(fx)
            cells_for_all_rows[i] = (note, new_fx)

    bytes_out = []
    current_length = -1
    
    i = 0
    while i < N:
        next_ne = i
        while next_ne < N and is_cell_empty(*cells_for_all_rows[next_ne]):
            next_ne += 1
            
        gap = next_ne - i
        
        # GAP 처리 (빈 줄 처리: 무조건 독립 딜레이 커맨드로 변환)
        while gap > 0:
            chunk = 256 if gap >= 256 else min(gap, 31)
            bytes_out.extend(emit_row(None, [('LEN', chunk)]))
            current_length = chunk
            gap -= chunk
            
        if next_ne == N:
            break
            
        note, fx_list = cells_for_all_rows[next_ne]
        
        # 이벤트 지속 거리(dist) 계산
        dist = 1
        for j in range(next_ne + 1, N):
            if not is_cell_empty(*cells_for_all_rows[j]):
                break
            dist += 1
            
        # 첫 번째 Chunk 분리 (현재 Row의 노트/이펙트를 포함)
        if note is not None:
            first_chunk = min(dist, 256)
            if first_chunk != current_length:
                fx_list.append(('LEN', first_chunk))
                current_length = first_chunk
            bytes_out.extend(emit_row(note, fx_list))
            remaining_dist = dist - first_chunk
        else:
            first_chunk = 256 if dist >= 256 else min(dist, 31)
            if first_chunk != current_length:
                fx_list.append(('LEN', first_chunk))
                current_length = first_chunk
            elif len(fx_list) == 0:
                # 이펙트조차 없다면 종료자가 없으므로 독립 딜레이 커맨드 강제 생성
                fx_list.append(('LEN', first_chunk))
            
            bytes_out.extend(emit_row(None, fx_list))
            remaining_dist = dist - first_chunk

        # 현재 이벤트를 기록하고 남은 틱들을 빈 GAP과 똑같이 처리
        while remaining_dist > 0:
            chunk = 256 if remaining_dist >= 256 else min(remaining_dist, 31)
            bytes_out.extend(emit_row(None, [('LEN', chunk)]))
            current_length = chunk
            remaining_dist -= chunk
            
        i = next_ne + dist
    
    # 마지막 바이트가 논터미네이팅 상태로 끝나는 경우 방어 로직
    if not bytes_out:
        bytes_out.append(0xE0) # Delay 1 강제 삽입
    else:
        last_b = bytes_out[-1]
        # Non-terminating 범위: $80~$9F (이펙트), $C0~$DF (Quick Inst)
        if (0x80 <= last_b <= 0x9F) or (0xC0 <= last_b <= 0xDF):
            bytes_out.append(0xE0) # Delay 1 강제 삽입하여 틱 종료 유도
        
    return bytes_out

def convert_furnace(input_path):
    with open(input_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    base_name = os.path.splitext(os.path.basename(input_path))[0]
    instruments = []
    songs = []
    idx = 0
    
    while idx < len(lines):
        line = lines[idx].strip()
        if '# Subsongs' in line:
            break
        
        if '- type: 1' in line:
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
            vol_macro = [15, 0xFF]
            while idx < len(lines):
                idx += 1
                l = lines[idx].strip()
                if l.startswith('- type:') or l.startswith('## ') or '# Subsongs' in l:
                    idx -= 1; break
                    
                if l.startswith('- vol:'):
                    lastindex = 0
                    looppoint = -1
                    parts = l.replace('- vol:', '').strip().split()
                    macro = []
                    for i, p in enumerate(parts):
                        if p == '|': looppoint = i
                        else: macro.append(int(p))
                        lastindex = i

                    if looppoint == -1:
                        looppoint = lastindex

                    macro.append(looppoint+16)
                    vol_macro = macro
            instruments.append({'type': 6, 'data': vol_macro})
        idx += 1

    current_song = None
    while idx < len(lines):
        line = lines[idx].strip()
        if line.startswith('- tick rate:'):
            current_song = {'speeds': [6], 'bpm': [150], 'patlen': 0, 'orders': [], 'patterns': {}}
            songs.append(current_song)
        elif line.startswith('- speeds:') and current_song is not None:
            current_song['speeds'] = int(line.split(': ')[1].split('/')[0])
        elif line.startswith('- virtual tempo:') and current_song is not None:
            current_song['bpm'] = int(line.split(': ')[1].split('/')[0])
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
                f.write("    " + to_byte_str([inst['data'][0], inst['data'][1]]) + "\n")
                for op in inst['data'][2:]:
                    f.write("    " + to_byte_str(op) + "\n")
            elif inst['type'] == 6:
                f.write("    " + to_byte_str(inst['data']) + "\n")
            f.write("\n")
    print(f"Generated {header_filename}")

    for i, song in enumerate(songs):
        song_filename = f"{base_name}_song{i:02d}.asm"
        with open(song_filename, 'w') as f:
            f.write(f"furEPSM_song{i:02d}:\n")
            f.write("    .WORD @frames\n")
            f.write(f"    .BYTE {len(song['orders'])} ; frame count\n")
            f.write(f"    .BYTE {song['patlen']} ; pattern length\n")
            f.write(f"    .BYTE {song['speeds']} ; speed\n")
            f.write(f"    .BYTE {song['bpm']} ; tempo\n")
            
            f.write("@frames:\n")
            for frm_idx in range(len(song['orders'])):
                f.write(f"    .WORD @frame{frm_idx}\n")
            f.write("\n")
            
            for frm_idx, order in enumerate(song['orders']):
                f.write(f"@frame{frm_idx}:\n")
                ptr_strs = []
                for ch in range(6): ptr_strs.append(f"@fm{ch+1}pat{order[ch]}")
                for ch in range(3): ptr_strs.append(f"@ssg{ch+1}pat{order[6+ch]}")
                # ptr_strs.append(f"@rhythmpat{order[9]}")
                f.write("    .WORD " + ", ".join(ptr_strs) + "\n\n")
                
            for pat_id, rows in song['patterns'].items():
                for ch in range(6):
                    f.write(f"@fm{ch+1}pat{pat_id}:\n")
                    ch_cells = [parse_cell(r[ch]) for r in rows]
                    b_out = generate_channel_data(ch_cells, is_rhythm=False)
                    f.write("    " + to_byte_str(b_out) + "\n")
                
                for ch in range(3):
                    f.write(f"@ssg{ch+1}pat{pat_id}:\n")
                    ch_cells = [parse_cell(r[6+ch]) for r in rows]
                    b_out = generate_channel_data(ch_cells, is_rhythm=False)
                    f.write("    " + to_byte_str(b_out) + "\n")

        print(f"Generated {song_filename}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python furnace2asm.py <input.txt>")
    else:
        convert_furnace(sys.argv[1])