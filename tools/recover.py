#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Återskapar intilliggande PAL-fält från paketlogg och rådata; tar in- och utmapp.
import csv,collections,json,sys
from pathlib import Path
if len(sys.argv)!=3:
 raise SystemExit('Usage: recover.py CAPTURE_DIRECTORY OUTPUT_DIRECTORY')
root=Path(sys.argv[1])
raw=(root/'video-usb.bin').read_bytes()
with (root/'videopaket.tsv').open() as f: rows=list(csv.DictReader(f,delimiter='\t'))
fields=[]; current=None
for row in rows:
 off,n=int(row['raw_offset']),int(row['byte']); data=raw[off:off+n]
 if len(data)!=n:
  raise ValueError('Packet outside raw file')
 if data[:2]==b'\x33\x95':
  if current is not None:fields.append(current)
  current=None
  continue
 if data[:2]==b'\x22\x5a':
  if current is not None:fields.append(current)
  current={'counter':data[2],'bytes':bytearray(),'errors':0,'frame':int(row['frame'])}
 if current is None:continue
 current['errors']+=row['status']!='00000000'
 if data[:2]==b'\x22\x5a' or data[:4]==b'\x88'*4:data=data[4:]
 current['bytes'].extend(data)
valid=[]
for f in fields:
 f['valid']=(len(f['bytes'])==414720 or (len(f['bytes'])==414724 and f['bytes'][-4:]==bytes.fromhex('c6930593'))) and f['errors']==0
 if f['valid']:valid.append(f)
pairs=[]
for a,b in zip(fields,fields[1:]):
 if a['valid'] and b['valid'] and a['counter']%2==0 and b['counter']==(a['counter']+1)%256:pairs.append((a,b))
if not pairs:raise SystemExit('No complete adjacent PAL frame pairs')
out=Path(sys.argv[2]);out.mkdir(parents=True,exist_ok=True)
with (out/'video-720x576.yuyv').open('wb') as stream:
 for a,b in pairs:
  frame=bytearray(720*576*2)
  for y in range(288):
   frame[(y*2)*1440:(y*2+1)*1440]=a['bytes'][y*1440:(y+1)*1440]
   frame[(y*2+1)*1440:(y*2+2)*1440]=b['bytes'][y*1440:(y+1)*1440]
  stream.write(frame)
  if stream.tell()==len(frame):(out/'first-frame.yuyv').write_bytes(frame)
report={'input_bytes':len(raw),'field_headers':len(fields)+(1 if current else 0),'complete_valid_fields':len(valid),'complete_frame_pairs':len(pairs),'frame_rate':25,'trailer':'c6930593','observed_field_bytes':414724,'image_field_bytes':414720,'first_frame_counters':[pairs[0][0]['counter'],pairs[0][1]['counter']],'invalid_field_lengths':dict(collections.Counter(len(f['bytes'])for f in fields if not f['valid']))}
(out/'recovery.json').write_text(json.dumps(report,indent=2)); print(json.dumps(report))
