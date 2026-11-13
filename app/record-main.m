// SPDX-License-Identifier: GPL-2.0-or-later
// Återanvänder testets registerjournal och USB-motor; ändrar bara strömmens mottagare och livslängd.
#define PG_RECORDER 1
#define main pg_probe_main
#include "../src/plexgear-pal.m"
#undef main
/* Kör inspelning eller offlineprov, slutför filmen och lämnar delmaterial kvar; tar arbetsmapp och slutfil. */
int main(int argc,const char *argv[]){@autoreleasepool{
 if(argc==4&&!strcmp(argv[1],"--mux"))return pg_mux([NSString stringWithUTF8String:argv[2]],[NSString stringWithUTF8String:argv[3]])?0:11;
 if(argc==5&&!strcmp(argv[1],"--replay")){
 NSString *dir=[NSString stringWithUTF8String:argv[4]];[[NSFileManager defaultManager]createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];PGMovie *movie=[[PGMovie alloc]initWithDirectory:dir epoch:0];if(!movie)return 20;
 NSData *raw=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[2]]];if(!raw||raw.length%(720*576*2))return 21;
 for(NSUInteger f=0;f<raw.length/(720*576*2);f++){@autoreleasepool{const uint8_t *src=(const uint8_t *)raw.bytes+f*720*576*2;uint8_t even[720*288*2],odd[720*288*2];for(int y=0;y<288;y++){memcpy(even+y*1440,src+y*2880,1440);memcpy(odd+y*1440,src+y*2880+1440,1440);}[movie field:even counter:(uint8_t)(f*2) time:f/25.0];[movie field:odd counter:(uint8_t)(f*2+1) time:f/25.0+0.02];usleep(40000);}}
 BOOL ok=[movie finish];NSString *wav=[NSString stringWithUTF8String:argv[3]];[[NSFileManager defaultManager]copyItemAtPath:wav toPath:[dir stringByAppendingPathComponent:@"wiiu-ljud.wav"] error:NULL];[@"{\"first_host_seconds\":0.000001}" writeToFile:[dir stringByAppendingPathComponent:@"audio-timing.json"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];return ok&&pg_mux(dir,[dir stringByAppendingPathComponent:@"replay.mov"])?0:22;
 }
 if(argc!=3){puts("Användning: recorder ARBETSMAPP UT.mov");return 1;}
 if([[NSFileManager defaultManager]fileExistsAtPath:[NSString stringWithUTF8String:argv[2]]])return 12;
 int status=pg_probe_main(2,argv);BOOL saved=pg_mux([NSString stringWithUTF8String:argv[1]],[NSString stringWithUTF8String:argv[2]]);
 if(saved)puts("FILMEN ÄR SPARAD. Delmaterialet finns kvar i arbetsmappen.");
 NSData *report=[NSData dataWithContentsOfFile:[[NSString stringWithUTF8String:argv[1]] stringByAppendingPathComponent:@"mux-report.json"]];NSDictionary *mux=report?[NSJSONSerialization JSONObjectWithData:report options:0 error:NULL]:nil;
 return saved?(status==8?8:status==0&&[mux[@"audio_included"] boolValue]?0:6):11;
}}
