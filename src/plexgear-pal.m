// SPDX-License-Identifier: GPL-2.0-or-later
// Bygger vidare på ARM64 v4 (MIT) och registersekvenser från Linux em28xx (GPL-2.0+).
// Linux-författare: Ludovico Cavedon, Markus Rechberger, Mauro Carvalho Chehab,
// Sascha Sommer, Frank Schäfer. Se KALLOR.txt och licensfilerna.
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <IOUSBHost/IOUSBHost.h>
#import <IOKit/IOKitLib.h>
#import "audio_capture.h"
#include "field_parser.h"
#include <signal.h>
#include <unistd.h>
#include <time.h>
#if !defined(__arm64__)
#error Programmet måste byggas för ARM64.
#endif
typedef struct {uint16_t reg;uint8_t value;} Setting;
static volatile sig_atomic_t stopped=0;
static dispatch_queue_t pgQueue;
static const Setting initSettings[]={
 {0x0f,0x87},{0x11,0x11},{0x12,0x67},{0x13,0},
 {0x14,0x20},{0x15,0x20},{0x16,0x20},{0x17,0x20},
 {0x18,0},{0x19,0},{0x1a,0},{0x1b,0},{0x1c,0},{0x1d,0},
 {0x1e,0xb4},{0x1f,0x3c},{0x20,0x10},{0x21,8},{0x22,0x10},
 {0x23,0},{0x24,0},{0x25,2},{0x26,0},{0x27,0x34},
 {0x3d,5},{0x3e,0},{0x3f,7}
};
static const Setting palSettings[]={
 {0x24,0},{0x25,2},{0x2e,0},{0x7a0b,0},{0xb6,0x8f},{0xb8,0},
 {0x7a1c,0x1e},{0x7a1d,0x99},{0x7a1e,0x99},{0x7a1f,0x9a},
 {0x7a20,0x3d},{0x7a21,0x3e},{0x7a29,0},{0x7a2f,0x52},{0x7a40,5},{0x7a51,0},{0x7ac1,0x1b},
 {0x38,1},{0xb1,0x70},{0xb3,0},{0xb5,0},{0x7a02,0x4f},{0x7a3f,1},{0x7a3f,0},
 {0x7a04,0xdc},{0x7a0c,0x67},{0x7a0f,0x1c},{0x7a18,0x28},{0x7a19,0x32},
 {0x7a1a,0xb9},{0x7a1b,0x86},{0x7a31,0xc3},{0x7a82,0x52},
 {0x7a00,0x32},{0x7a01,0x10},{0x7a03,6},{0x7a07,0x2f},{0x7a08,0x77},
 {0x7a09,0x0f},{0x7a0a,0x8c},{0x7a20,0x3d},{0x7a2e,0x88},{0x7a30,0x2c},{0x7a80,7},
 {0x7a3f,1},{0x7a3f,0},

};
// PAL 576i: 288 linjer per fält. Originalets PAL-höjdregister är 0x48.
static const Setting geometrySettings[]={
 {0x10,0x10},{0x11,0x11},{0x27,0x34},{0x1b,0},{0x1c,0},{0x1d,0},
 {0x1e,0xb4},{0x1f,0x48},{0x26,0},{0x30,0},{0x31,0},{0x32,0},{0x33,0},
 {0x48,0},{0x12,0x67}
};
/* Returnerar monoton tid i sekunder; tar inga argument. */
static double pgNow(void){struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1e9;}
/* Tar en signal, begär ordnad avslutning och returnerar inget. */
static void stopHandler(int signalNumber){(void)signalNumber;stopped=1;}
/* Läser/skriver en byte i ett register via Apples USB-API; tar objekt, register, bytepekare och riktning och returnerar status. */
static BOOL hardwareTransfer(IOUSBHostObject *usb,uint16_t reg,uint8_t *value,BOOL writing){
    IOUSBDeviceRequest request={0};request.bmRequestType=writing?0x40:0xc0;
    request.wIndex=OSSwapHostToLittleInt16(reg);request.wLength=OSSwapHostToLittleInt16(1);
    NSMutableData *data=[NSMutableData dataWithLength:1];if(writing)((uint8_t *)data.mutableBytes)[0]=*value;
    NSError *error=nil;NSUInteger actual=0;
    BOOL ok=[usb sendDeviceRequest:request data:data bytesTransferred:&actual completionTimeout:1 error:&error];
    if(!ok||actual!=1){printf("%s register %04x: fel %ld, %s\n",writing?"Skrivning":"Läsning",reg,(long)error.code,error.localizedDescription.UTF8String?:"kort svar");return NO;}
    if(!writing)*value=((const uint8_t *)data.bytes)[0];return YES;
}
/* Hittar och öppnar endast 1b80:e600, gränssnitt 0; tar inga argument och returnerar öppnat objekt eller nil. */
static IOUSBHostInterface *openVideo(void){
    io_iterator_t iterator=0;kern_return_t result=IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("IOUSBHostInterface"),&iterator);
    if(result!=KERN_SUCCESS){printf("Kan inte lista USB-gränssnitt: %08x\n",result);return nil;}
    io_service_t candidate=0,service=0;
    while((candidate=IOIteratorNext(iterator))){
        CFMutableDictionaryRef raw=NULL;NSDictionary *p=nil;
        if(IORegistryEntryCreateCFProperties(candidate,&raw,kCFAllocatorDefault,0)==KERN_SUCCESS)p=CFBridgingRelease(raw);
        if([p[@"idVendor"] unsignedIntValue]==0x1b80&&[p[@"idProduct"] unsignedIntValue]==0xe600&&p[@"bInterfaceNumber"]&&[p[@"bInterfaceNumber"] unsignedIntValue]==0){service=candidate;break;}
        IOObjectRelease(candidate);
    }
    IOObjectRelease(iterator);if(!service){puts("Videogränssnittet hittades inte.");return nil;}
    NSError *error=nil;IOUSBHostInterface *usb=[[IOUSBHostInterface alloc]initWithIOService:service options:IOUSBHostObjectInitOptionsNone queue:pgQueue error:&error interestHandler:nil];
    IOObjectRelease(service);if(!usb)printf("USB-öppning misslyckades: %s\n",error.description.UTF8String);return usb;
}

@interface PGRegisters:NSObject
@property IOUSBHostInterface *usb;
@property NSMutableDictionary<NSNumber *,NSNumber *> *saved;
@property NSMutableOrderedSet<NSNumber *> *changed;
-(instancetype)initWithUSB:(IOUSBHostInterface *)usb;
-(BOOL)prepare:(NSString *)directory;
-(BOOL)write:(uint16_t)reg value:(uint8_t)value;
-(BOOL)apply:(const Setting *)table count:(size_t)count;
-(BOOL)restore;
@end
@implementation PGRegisters
/* Skapar en registerjournal för ett öppnat videogränssnitt; returnerar journalen. */
-(instancetype)initWithUSB:(IOUSBHostInterface *)usb{if((self=[super init])){_usb=usb;_saved=[NSMutableDictionary dictionary];_changed=[NSMutableOrderedSet orderedSet];}return self;}
/* Säkerhetskopierar alla register i de tre tabellerna före första skrivning; tar resultatmapp och returnerar status. */
-(BOOL)prepare:(NSString *)directory{
    const Setting *tables[]={initSettings,palSettings,geometrySettings};size_t counts[]={sizeof(initSettings)/sizeof(Setting),sizeof(palSettings)/sizeof(Setting),sizeof(geometrySettings)/sizeof(Setting)};
    for(size_t t=0;t<3;t++)for(size_t i=0;i<counts[t];i++){NSNumber *key=@(tables[t][i].reg);if(self.saved[key])continue;uint8_t value=0;if(!hardwareTransfer(self.usb,key.unsignedShortValue,&value,NO))return NO;self.saved[key]=@(value);}
    NSMutableDictionary *json=[NSMutableDictionary dictionary];for(NSNumber *key in self.saved)json[[NSString stringWithFormat:@"%04x",key.unsignedIntValue]]=self.saved[key];
    NSError *error=nil;NSData *data=[NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingPrettyPrinted error:&error];
    return data&&[data writeToFile:[directory stringByAppendingPathComponent:@"register-fore.json"] options:NSDataWritingAtomic error:&error];
}
/* Skriver en journalförd byte; tar register och värde och returnerar status. */
-(BOOL)write:(uint16_t)reg value:(uint8_t)value{if(!self.saved[@(reg)])return NO;[self.changed addObject:@(reg)];return hardwareTransfer(self.usb,reg,&value,YES);}
/* Använder en avläst tabell och stannar vid första felet; tar tabell och antal och returnerar status. */
-(BOOL)apply:(const Setting *)table count:(size_t)count{for(size_t i=0;i<count;i++){if(stopped||![self write:table[i].reg value:table[i].value])return NO;}return YES;}
/* Återställer journalförda register och verifierar återläsning; tar inga argument och returnerar status. */
-(BOOL)restore{
    if(!self.changed.count)return YES;
    uint8_t value=0;BOOL ok=YES;NSUInteger failures=0;
    if([self.changed containsObject:@0x12]){if(hardwareTransfer(self.usb,0x12,&value,NO)){value&=(uint8_t)~0x40;if(!hardwareTransfer(self.usb,0x12,&value,YES))failures++;}else failures++;}
    for(NSNumber *key in self.changed.reverseObjectEnumerator){if(key.unsignedIntValue==0x0f||key.unsignedIntValue==0x12)continue;value=self.saved[key].unsignedCharValue;if(!hardwareTransfer(self.usb,key.unsignedShortValue,&value,YES)){ok=NO;if(++failures>=3){puts("Återställningen avbryts efter upprepade USB-fel. Koppla ur och återanslut.");return NO;}}}
    if([self.changed containsObject:@0x7a3f]){uint8_t one=1,zero=0;value=self.saved[@0x7a3f].unsignedCharValue;if(!hardwareTransfer(self.usb,0x7a3f,&one,YES)||!hardwareTransfer(self.usb,0x7a3f,&zero,YES)||!hardwareTransfer(self.usb,0x7a3f,&value,YES))ok=NO;}
    for(NSNumber *key in @[@0x0f,@0x12])if([self.changed containsObject:key]){value=self.saved[key].unsignedCharValue;if(!hardwareTransfer(self.usb,key.unsignedShortValue,&value,YES))ok=NO;}
    for(NSNumber *key in self.changed){if(!hardwareTransfer(self.usb,key.unsignedShortValue,&value,NO)){ok=NO;if(++failures>=3)break;}else if(value!=self.saved[key].unsignedCharValue){printf("Återläsning efter återställning avviker i %04x: före=%02x efter=%02x.\n",key.unsignedIntValue,self.saved[key].unsignedCharValue,value);ok=NO;}}
    puts(ok?"Registeråterställning verifierad. Intern dekoderstatus är inte separat verifierad.":"Fullständig registeråterställning inte verifierad. Koppla ur och återanslut digitaliseraren.");return ok;
}
@end

/* Begränsar en RGB-kanal till en byte; tar ett heltal och returnerar kanalen. */
static uint8_t pgClip(int v){return v<0?0:v>255?255:v;}
/* Konverterar ett komplett PAL-fält till linjedubblad 4:3-PNG; tar fält och filsökväg och returnerar status. */
static BOOL saveFieldPNG(const uint8_t *src,NSString *path){
    NSBitmapImageRep *image=[[NSBitmapImageRep alloc]initWithBitmapDataPlanes:NULL pixelsWide:768 pixelsHigh:576 bitsPerSample:8 samplesPerPixel:3 hasAlpha:NO isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:768*3 bitsPerPixel:24];if(!image)return NO;
    uint8_t *out=image.bitmapData;
    for(int y=0;y<576;y++)for(int x=0;x<768;x++){int sx=x*720/768;size_t p=((size_t)(y/2)*720+(sx&~1))*2;int c=src[p+(sx&1)*2]-16,u=src[p+1]-128,v=src[p+3]-128;size_t d=((size_t)y*768+x)*3;out[d]=pgClip((298*c+409*v+128)>>8);out[d+1]=pgClip((298*c-100*u-208*v+128)>>8);out[d+2]=pgClip((298*c+516*u+128)>>8);}
    return [[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}]writeToFile:path atomically:YES];
}

@interface PGBuffer:NSObject
@property NSMutableData *data;
@property NSMutableData *transactions;
@property uint64_t frame;
@end
@implementation PGBuffer
/* Skapar en buffert för 64 mikrointervall à 3072 byte; tar inga argument och returnerar bufferten. */
-(instancetype)init{if((self=[super init])){_data=[NSMutableData dataWithLength:64*3072];_transactions=[NSMutableData dataWithLength:64*sizeof(IOUSBHostIsochronousTransaction)];}return self;}
@end

@interface PGStream:NSObject {
@public
    PGFieldParser *_parser;
    IOUSBHostInterface *_usb;IOUSBHostPipe *_pipe;
    dispatch_group_t _group;NSMutableArray<PGBuffer *> *_buffers;NSString *_directory;
    FILE *_raw,*_log;BOOL _running,_failed,_pngSaved,_fieldSeen;NSData *_firstField;int _firstParity;uint64_t _nextFrame,_bytes,_packets,_badPackets;double _deadline;
}
-(instancetype)initWithUSB:(IOUSBHostInterface *)usb pipe:(IOUSBHostPipe *)pipe directory:(NSString *)directory;
-(BOOL)submit:(PGBuffer *)buffer;
-(void)completed:(PGBuffer *)buffer status:(IOReturn)status;
-(BOOL)run;
@end

/* Tar emot ett komplett fält från C-parsern och sparar första stillbilden; returnerar inget. */
static void fieldReady(const uint8_t *field,size_t length,int parity,void *context){
    PGStream *stream=(__bridge PGStream *)context;
    if(stream->_fieldSeen)return;stream->_fieldSeen=YES;
    stream->_firstField=[NSData dataWithBytes:field length:length];stream->_firstParity=parity;
    printf("Första kompletta fältet mottaget: %zu byte, paritet %d. PNG skapas efter att USB-kön tömts.\n",length,parity);
}
@implementation PGStream
/* Öppnar diagnostikfiler och allokerar parser och buffertar för en köad isokron ström; returnerar objekt eller nil. */
-(instancetype)initWithUSB:(IOUSBHostInterface *)usb pipe:(IOUSBHostPipe *)pipe directory:(NSString *)directory{
    if((self=[super init])){_usb=usb;_pipe=pipe;_directory=[directory copy];_group=dispatch_group_create();_buffers=[NSMutableArray array];_parser=calloc(1,sizeof(*_parser));if(!_parser)return nil;pg_init(_parser,fieldReady,(__bridge void *)self);
        _raw=fopen([directory stringByAppendingPathComponent:@"video-usb.bin"].fileSystemRepresentation,"wb");_log=fopen([directory stringByAppendingPathComponent:@"videopaket.tsv"].fileSystemRepresentation,"w");if(!_raw||!_log)return nil;
        fprintf(_log,"frame\tmikro\tstatus\tbyte\traw_offset\tforsta_8_byte\n");for(int i=0;i<4;i++)[_buffers addObject:[PGBuffer new]];
    }return self;
}
/* Frigör resurser efter att sista callbacken släppt sitt ägarskap; tar inga argument och returnerar inget. */
-(void)dealloc{if(_raw)fclose(_raw);if(_log)fclose(_log);free(_parser);}
/* Köar 8 ms data i framtida USB-frames och räknar utestående begäran; tar bufferten och returnerar om köningen lyckades. */
-(BOOL)submit:(PGBuffer *)buffer{
    IOUSBHostIsochronousTransaction *t=buffer.transactions.mutableBytes;
    memset(t,0,buffer.transactions.length);for(int i=0;i<64;i++){t[i].status=kIOReturnInvalid;t[i].offset=i*3072;t[i].requestCount=3072;}
    buffer.frame=_nextFrame;_nextFrame+=8;dispatch_group_enter(_group);NSError *error=nil;
    BOOL queued=[_pipe enqueueIORequestWithData:buffer.data transactionList:t transactionListCount:64 firstFrameNumber:buffer.frame options:IOUSBHostIsochronousTransferOptionsNone error:&error completionHandler:^(IOReturn status,IOUSBHostIsochronousTransaction *transactions){
        (void)transactions;@autoreleasepool{[self completed:buffer status:status];if(self->_running&&!self->_failed&&!stopped&&pgNow()<self->_deadline)[self submit:buffer];dispatch_group_leave(self->_group);}
    }];
    if(!queued){printf("Kunde inte köa isokron video: %s\n",error.description.UTF8String);_failed=YES;_running=NO;dispatch_group_leave(_group);}return queued;
}
/* Tolkar ett avslutat USB-block och sparar paket med gränser; tar buffert och övergripande status och returnerar inget. */
-(void)completed:(PGBuffer *)buffer status:(IOReturn)status{
    if(status!=kIOReturnSuccess){if(!_failed)printf("Isokron video stoppas efter transportfel 0x%08x.\n",(unsigned)status);_failed=YES;_running=NO;}
    IOUSBHostIsochronousTransaction *t=buffer.transactions.mutableBytes;const uint8_t *base=buffer.data.bytes;
    for(int i=0;i<64;i++){_packets++;size_t n=t[i].completeCount,offset=t[i].offset;
        if(n>3072||offset>buffer.data.length||n>buffer.data.length-offset){_failed=YES;_running=NO;pg_feed(_parser,NULL,0,0);continue;}
        const uint8_t *p=base+offset;fprintf(_log,"%llu\t%d\t%08x\t%zu\t%llu\t",(unsigned long long)buffer.frame,i,(unsigned)t[i].status,n,(unsigned long long)_bytes);
        for(size_t j=0;j<MIN(n,8);j++)fprintf(_log,"%02x",p[j]);fputc('\n',_log);
        BOOL success=status==kIOReturnSuccess&&t[i].status==kIOReturnSuccess;if(!success)_badPackets++;
        if(n){if(_bytes+n>64*1024*1024||fwrite(p,1,n,_raw)!=n){_failed=YES;_running=NO;pg_feed(_parser,NULL,0,0);break;}_bytes+=n;}
        pg_feed(_parser,p,n,success);
    }
}
/* Håller fyra USB-begäranden köade i cirka tre sekunder och tömmer kön; returnerar om en fullständig fältbild sparades. */
-(BOOL)run{
    dispatch_sync(pgQueue,^{uint64_t current=[self->_usb frameNumberWithTime:NULL];if(!current){puts("Kan inte läsa USB-kontrollerns frame-nummer. Ingen köad överföring startas.");self->_failed=YES;return;}self->_running=YES;self->_deadline=pgNow()+3;self->_nextFrame=current+20;for(PGBuffer *buffer in self->_buffers){if(![self submit:buffer])break;}});
    long wait=dispatch_group_wait(_group,dispatch_time(DISPATCH_TIME_NOW,6*NSEC_PER_SEC));
    if(wait){dispatch_sync(pgQueue,^{self->_running=NO;self->_failed=YES;});NSError *error=nil;[_pipe abortWithError:&error];wait=dispatch_group_wait(_group,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC));if(wait){puts("USB-kön kunde inte tömmas. Ingen fortsatt bildtolkning godkänns.");return NO;}}
    dispatch_sync(pgQueue,^{self->_running=NO;if(self->_raw)fflush(self->_raw);if(self->_log)fflush(self->_log);});
    if(_firstField){BOOL rawOK=[_firstField writeToFile:[_directory stringByAppendingPathComponent:@"forsta-faltet.yuyv"] atomically:YES];_pngSaved=saveFieldPNG(_firstField.bytes,[_directory stringByAppendingPathComponent:@"wiiu-forsta-bild.png"]);printf("Stillbild från paritet %d: råfält=%s, 4:3-PNG=%s.\n",_firstParity,rawOK?"sparat":"fel",_pngSaved?"sparad":"fel");}
    printf("Video: %llu byte, %llu paket, %llu paket med fel; fälthuvuden=%llu, kompletta=%llu, underkända=%llu, VBI=%llu.\n",(unsigned long long)_bytes,(unsigned long long)_packets,(unsigned long long)_badPackets,(unsigned long long)_parser->headers,(unsigned long long)_parser->complete,(unsigned long long)_parser->rejected,(unsigned long long)_parser->vbi);
    return !_failed&&_pngSaved;
}
@end

/* Kontrollerar att samma videoändpunkt som i v4 finns i USB-beskrivningen; tar videoobjektet och returnerar status. */
static BOOL expectedEndpoint(IOUSBHostInterface *usb){
    const IOUSBConfigurationDescriptor *cfg=usb.configurationDescriptor;if(!cfg)return NO;const uint8_t *bytes=(const uint8_t *)cfg;size_t length=OSSwapLittleToHostInt16(cfg->wTotalLength);BOOL target=NO;
    for(size_t p=0;p+2<=length;){uint8_t n=bytes[p],type=bytes[p+1];if(n<2||p+n>length)break;const uint8_t *d=bytes+p;if(type==4&&n>=9)target=d[2]==0&&d[3]==7;if(target&&type==5&&n>=7&&d[2]==0x82&&(d[3]&3)==1){uint16_t packet=d[4]|(d[5]<<8);return(packet&0x7ff)*(1+((packet>>11)&3))==3072&&d[6]==1;}p+=n;}return NO;
}

/* Initierar PAL, provar köad video och separat USB-ljud och återställer enheten; tar resultatmapp och ljudval och returnerar status. */
static int capturePAL(NSString *directory,BOOL useAudio){
    IOUSBHostInterface *usb=openVideo();if(!usb)return 2;PGRegisters *journal=[[PGRegisters alloc]initWithUSB:usb];uint8_t oldAlt=usb.interfaceDescriptor->bAlternateSetting;BOOL altChanged=NO;PGAudio *audio=NULL;int status=5;
    @try{do{
        uint8_t chip=0;if(!hardwareTransfer(usb,0x0a,&chip,NO)||chip!=146){puts("Förväntat krets-id 146 saknas. Inga register ändras.");break;}
        if(!expectedEndpoint(usb)){puts("Förväntad ändpunkt saknas. Inga register ändras.");break;}
        if(![journal prepare:directory]){puts("Registersäkerthetskopiering misslyckades. Inga register ändras.");break;}
        if(![journal apply:initSettings count:sizeof(initSettings)/sizeof(Setting)]||![journal write:0x12 value:0x27])break;
        if(![journal apply:palSettings count:sizeof(palSettings)/sizeof(Setting)]||![journal apply:geometrySettings count:sizeof(geometrySettings)/sizeof(Setting)])break;
        usleep(100000);
        for(NSNumber *reg in @[@0x0f,@0x10,@0x11,@0x12,@0x1e,@0x1f,@0x7a3a,@0x7a3b,@0x7a3c]){uint8_t value=0;if(!hardwareTransfer(usb,reg.unsignedShortValue,&value,NO)){status=7;goto finish;}printf("Status %04x=%02x\n",reg.unsignedIntValue,value);}
        NSError *error=nil;if(![usb selectAlternateSetting:7 error:&error]){printf("Alt 7 misslyckades: %s\n",error.description.UTF8String);break;}altChanged=YES;
        IOUSBHostPipe *pipe=[usb copyPipeWithAddress:0x82 error:&error];if(!pipe){printf("Videopipe saknas: %s\n",error.description.UTF8String);break;}
        PGStream *stream=[[PGStream alloc]initWithUSB:usb pipe:pipe directory:directory];if(!stream){puts("Kan inte skapa videobuffertar eller resultatfiler.");break;}
        if(useAudio)audio=pg_audio_start(directory);
        puts("Provar Wii U: PAL 576i, komposit, 4:3. Fyra videobuffertar hålls köade under cirka tre sekunder.");
        BOOL image=[stream run];BOOL audioOK=pg_audio_stop(audio);audio=NULL;
        uint8_t healthy=0;BOOL control=hardwareTransfer(usb,0x0a,&healthy,NO)&&healthy==146;
        printf("Resultat: komplett fältbild=%s, USB-ljud med icke-nollprover=%s, kontrollkanal=%s.\n",image?"JA":"NEJ",audioOK?"JA":"NEJ",control?"OK":"fel");
        status=(image&&audioOK&&control)?0:6;
    }while(0);finish:;}
    @catch(NSException *exception){printf("Programfel: %s\n",exception.reason.UTF8String);status=7;}
    @finally{if(audio){pg_audio_stop(audio);audio=NULL;}NSError *error=nil;if(altChanged&&![usb selectAlternateSetting:oldAlt error:&error]){puts("Alt-läget kunde inte återställas. Koppla ur och återanslut.");status=8;}if(![journal restore])status=8;[usb destroy];}
    return status;
}

/* Skapar resultatmapp och kör ARM64-testet; tar CLI-argument och returnerar slutkod. */
int main(int argc,const char *argv[]){@autoreleasepool{
    if(argc!=2){puts("Användning: plexgear-pal RESULTATMAPP");return 1;}setvbuf(stdout,NULL,_IOLBF,0);signal(SIGINT,stopHandler);signal(SIGTERM,stopHandler);
    puts("Plexgear ARM64 v5.1: experimentell PAL 576i/4:3 och separat USB-ljud. Ingen Rosetta.");
    puts("Förväntad källa: Wii U via gul kompositvideo och röd/vit ljudingång. Låt bild och ljud spelas upp.");
    BOOL audio=pg_audio_permission();NSString *directory=[NSString stringWithUTF8String:argv[1]];NSError *error=nil;
    if(![[NSFileManager defaultManager]createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]){printf("Kan inte skapa resultatmapp: %s\n",error.description.UTF8String);return 1;}
    pgQueue=dispatch_queue_create("se.segersvard.plexgear.video",DISPATCH_QUEUE_SERIAL);return capturePAL(directory,audio);
}}
