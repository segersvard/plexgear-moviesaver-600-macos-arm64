#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
import struct,wave,json,sys
from pathlib import Path
# QuickTime-container med standardiserade JPEG-bildrutor och okomprimerat PCM-ljud.
def u16(x):
    """Packar ett 16-bitars tal i nätverksordning."""
    return struct.pack('>H',x)
def u32(x):
    """Packar ett 32-bitars tal i nätverksordning."""
    return struct.pack('>I',x)
def atom(name,data):
    """Skapar en QuickTime/ISO-BMFF-atom av typ och nyttolast."""
    return u32(8+len(data))+name.encode('ascii')+data
def full(name,data,flags=0):
    """Skapar en atom med version 0 och angivna flaggor."""
    return atom(name,u32(flags)+data)
def table(name,entries):
    """Skapar en räknad tabell av redan packade poster."""
    return full(name,u32(len(entries))+b''.join(entries))
mat=b''.join(u32(x)for x in [0x10000,0,0,0,0x10000,0,0,0,0x40000000])
dref=atom('dinf',table('dref',[full('url ',b'',1)]))
def track(track_id,kind,time_scale,sample_count,delta,sample_entry,sizes,offsets,samples_per_chunk):
    """Bygger ett komplett video- eller ljudspår med sampelstorlekar och filpositioner."""
    isvideo=kind=='vide';duration=round(sample_count*delta*1000/time_scale)
    tkhd=full('tkhd',u32(0)+u32(0)+u32(track_id)+u32(0)+u32(duration)+b'\0'*8+u16(0)+u16(0)+u16(0 if isvideo else 0x100)+u16(0)+mat+u32(768<<16 if isvideo else 0)+u32(576<<16 if isvideo else 0),7)
    mdhd=full('mdhd',u32(0)+u32(0)+u32(time_scale)+u32(sample_count*delta)+u16(0x55c4)+u16(0))
    hdlr=full('hdlr',u32(0)+kind.encode()+b'\0'*12+(b'Video\0' if isvideo else b'Audio\0'))
    media_header=full('vmhd',u16(0)+u16(0)*3,1) if isvideo else full('smhd',u16(0)+u16(0))
    stsd=table('stsd',[sample_entry]);stts=table('stts',[u32(sample_count)+u32(delta)])
    stsc=table('stsc',[u32(1)+u32(samples_per_chunk)+u32(1)])
    stsz=full('stsz',u32(0)+u32(sample_count)+b''.join(u32(s)for s in sizes)) if isvideo else full('stsz',u32(4)+u32(sample_count))
    stco=table('stco',[u32(o)for o in offsets])
    stbl=atom('stbl',stsd+stts+stsc+stsz+stco)
    return atom('trak',tkhd+atom('mdia',mdhd+hdlr+atom('minf',media_header+dref+stbl))),duration
if len(sys.argv)!=4:
    raise SystemExit('Usage: make-mov.py JPEG_DIRECTORY AUDIO_WAV OUTPUT_MOV')
frames=[p.read_bytes() for p in sorted(Path(sys.argv[1]).glob('*.jpg'))]
if not frames:raise SystemExit('No JPEG frames')
with wave.open(sys.argv[2]) as w:
    if (w.getnchannels(),w.getsampwidth(),w.getframerate())!=(2,2,48000):
        raise SystemExit('Expected stereo 48 kHz 16-bit PCM WAV')
    audio_count=w.getnframes();audio=w.readframes(audio_count)
ftyp=atom('ftyp',b'qt  '+u32(0)+b'qt  ')
start=len(ftyp)+8;offsets=[];pos=start
for frame in frames:offsets.append(pos);pos+=len(frame)
audio_offset=pos
compressor=b'Photo - JPEG';label=bytes([len(compressor)])+compressor+b'\0'*(31-len(compressor))
visual=atom('jpeg',b'\0'*6+u16(1)+u16(0)+u16(0)+u32(0)+u32(0)+u32(1024)+u16(768)+u16(576)+u32(72<<16)+u32(72<<16)+u32(0)+u16(1)+label+u16(24)+u16(0xffff))
sound=atom('sowt',b'\0'*6+u16(1)+u16(0)+u16(0)+u32(0)+u16(2)+u16(16)+u16(0)+u16(0)+u32(48000<<16))
video_track,video_duration=track(1,'vide',25,len(frames),1,visual,[len(x)for x in frames],offsets,1)
audio_track,audio_duration=track(2,'soun',48000,audio_count,1,sound,[],[audio_offset],audio_count)
mvhd=full('mvhd',u32(0)+u32(0)+u32(1000)+u32(max(video_duration,audio_duration))+u32(0x10000)+u16(0x100)+b'\0'*10+mat+b'\0'*24+u32(3))
movie=ftyp+atom('mdat',b''.join(frames)+audio)+atom('moov',mvhd+video_track+audio_track)
Path(sys.argv[3]).write_bytes(movie)
print(json.dumps({'file_bytes':len(movie),'video_frames':len(frames),'video_seconds':video_duration/1000,'audio_seconds':audio_count/48000,'codec':'Motion JPEG + PCM stereo','sync':'not verified'}))
