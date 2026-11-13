// SPDX-License-Identifier: GPL-2.0-or-later
#import "movie.h"
#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#include <stdatomic.h>
#include <unistd.h>
@interface PGMovie(){
 dispatch_queue_t _queue; atomic_int _pending; atomic_bool _bad;
 AVAssetWriter *_writer; AVAssetWriterInput *_input; CMVideoFormatDescriptionRef _format;
 NSString *_directory; NSData *_even; uint8_t _counter; double _evenTime,_epoch,_lastPreview;
 uint64_t _frames,_dropped; BOOL _finished;
}
@end
/* Begränsar beräknad RGB-kanal till en byte; tar heltal och returnerar kanalen. */
static uint8_t channel(int v){return v<0?0:v>255?255:v;}
@implementation PGMovie
/* Öppnar MOV-skrivaren för JPEG-komprimerade bildrutor; tar mapp och värdtid och returnerar objekt eller nil. */
-(instancetype)initWithDirectory:(NSString *)directory epoch:(double)epoch{
 if((self=[super init])){_directory=directory;_epoch=epoch;_queue=dispatch_queue_create("se.segersvard.moviesaver.writer",DISPATCH_QUEUE_SERIAL);atomic_init(&_pending,0);atomic_init(&_bad,false);
 NSError *error=nil;_writer=[[AVAssetWriter alloc]initWithURL:[NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"video.mov"]] fileType:AVFileTypeQuickTimeMovie error:&error];
 if(!_writer||CMVideoFormatDescriptionCreate(NULL,kCMVideoCodecType_JPEG,768,576,NULL,&_format)!=noErr)return nil;
 _input=[AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:nil sourceFormatHint:_format];_input.expectsMediaDataInRealTime=YES;
 if(![_writer canAddInput:_input])return nil;[_writer addInput:_input];if(![_writer startWriting]){puts(_writer.error.description.UTF8String);return nil;}[_writer startSessionAtSourceTime:kCMTimeZero];
 }return self;
}
/* Frigör formatbeskrivningen; tar inga argument och returnerar inget. */
-(void)dealloc{if(_format)CFRelease(_format);}
/* Läser trådsäker felstatus; tar inga argument och returnerar status. */
-(BOOL)failed{return atomic_load(&_bad);}
/* Anpassar tidsorigo till USB-starten innan skrivkön används; tar sekunder och returnerar inget. */
-(void)setEpoch:(double)epoch{_epoch=epoch;}
/* Konverterar två sammanhängande fält till JPEG och skriver en tidsstämplad bild; returnerar inget. */
-(void)encode:(NSData *)odd time:(double)time{
 NSBitmapImageRep *image=[[NSBitmapImageRep alloc]initWithBitmapDataPlanes:NULL pixelsWide:768 pixelsHigh:576 bitsPerSample:8 samplesPerPixel:3 hasAlpha:NO isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:768*3 bitsPerPixel:24];if(!image){atomic_store(&_bad,true);return;}
 for(int y=0;y<576;y++){const uint8_t *src=(y&1)?odd.bytes:_even.bytes;src+=(y/2)*1440;uint8_t *dst=image.bitmapData+y*768*3;
 for(int x=0;x<768;x++){int sx=x*720/768;size_t p=(sx&~1)*2;int c=src[p+(sx&1)*2]-16,u=src[p+1]-128,v=src[p+3]-128;dst[x*3]=channel((298*c+409*v+128)>>8);dst[x*3+1]=channel((298*c-100*u-208*v+128)>>8);dst[x*3+2]=channel((298*c+516*u+128)>>8);}}
 NSData *jpeg=[image representationUsingType:NSBitmapImageFileTypeJPEG properties:@{NSImageCompressionFactor:@0.92}];if(!jpeg){atomic_store(&_bad,true);return;}
 if(!_input.readyForMoreMediaData){_dropped++;return;}
 CMBlockBufferRef block=NULL;CMSampleBufferRef sample=NULL;OSStatus status=CMBlockBufferCreateWithMemoryBlock(NULL,NULL,jpeg.length,NULL,NULL,0,jpeg.length,0,&block);
 if(status==noErr)status=CMBlockBufferReplaceDataBytes(jpeg.bytes,block,0,jpeg.length);
 CMSampleTimingInfo timing={CMTimeMake(1,25),CMTimeMakeWithSeconds(MAX(0,_evenTime-_epoch),1000000),kCMTimeInvalid};size_t size=jpeg.length;
 if(status==noErr)status=CMSampleBufferCreateReady(NULL,block,_format,1,1,&timing,1,&size,&sample);
 if(status!=noErr||![_input appendSampleBuffer:sample]){atomic_store(&_bad,true);puts(_writer.error.description.UTF8String?:"Videorutan kunde inte skrivas.");}else _frames++;
 if(sample)CFRelease(sample);if(block)CFRelease(block);
 if(time-_lastPreview>=0.5){[jpeg writeToFile:[_directory stringByAppendingPathComponent:@"preview.jpg"] atomically:YES];_lastPreview=time;printf("Bildrutor: %llu. Tappade bildpar: %llu.\n",(unsigned long long)_frames,(unsigned long long)_dropped);}
}
/* Begränsar kön till sex fält och parar endast intilliggande räknare med rimligt PAL-avstånd; tar fält, räknare och tid. */
-(void)field:(const uint8_t *)bytes counter:(uint8_t)counter time:(double)time{
 if(self.failed)return;if(atomic_fetch_add(&_pending,1)>=6){atomic_fetch_sub(&_pending,1);return;}
 NSData *data=[NSData dataWithBytes:bytes length:720*288*2];
 dispatch_async(_queue,^{@autoreleasepool{
 if(!(counter&1)){self->_even=data;self->_counter=counter;self->_evenTime=time;}
 else {if(self->_even&&(uint8_t)(self->_counter+1)==counter&&time-self->_evenTime>0.01&&time-self->_evenTime<0.03)[self encode:data time:time];self->_even=nil;}
 atomic_fetch_sub(&self->_pending,1);
 }});
}
/* Slutför MOV efter alla köade fält och sparar starttid; tar inga argument och returnerar status. */
-(BOOL)finish{
 if(_finished)return !self.failed;_finished=YES;dispatch_sync(_queue,^{});
 if(!_frames){[_writer cancelWriting];return NO;}[_input markAsFinished];dispatch_semaphore_t done=dispatch_semaphore_create(0);[_writer finishWritingWithCompletionHandler:^{dispatch_semaphore_signal(done);}];
 if(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,60*NSEC_PER_SEC))||_writer.status!=AVAssetWriterStatusCompleted){atomic_store(&_bad,true);return NO;}
 [@{ @"epoch":@(_epoch),@"frames":@(_frames),@"writer_dropped_pairs":@(_dropped)}.description writeToFile:[_directory stringByAppendingPathComponent:@"video-timing.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
 NSData *json=[NSJSONSerialization dataWithJSONObject:@{@"epoch":@(_epoch),@"frames":@(_frames)} options:0 error:NULL];[json writeToFile:[_directory stringByAppendingPathComponent:@"video-timing.json"] atomically:YES];return !self.failed;
}
@end
/* Laddar lokal JSON-tidsinformation från en fil; tar sökväg och returnerar ordlista eller nil. */
static NSDictionary *timingFile(NSString *path){NSData *data=[NSData dataWithContentsOfFile:path];return data?[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;}
/* Sammanfogar MOV och WAV med startförskjutning; tar arbetsmapp och slutfil och returnerar status. */
BOOL pg_mux(NSString *directory,NSString *output){
 if([[NSFileManager defaultManager]fileExistsAtPath:output]){puts("Målfilen finns redan. Den skrivs inte över.");return NO;}
 AVURLAsset *video=[AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"video.mov"]] options:nil];
 AVURLAsset *audio=[AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"wiiu-ljud.wav"]] options:nil];
 AVAssetTrack *v=[[video tracksWithMediaType:AVMediaTypeVideo]firstObject],*a=[[audio tracksWithMediaType:AVMediaTypeAudio]firstObject];if(!v){puts("Videospår saknas. Delmaterialet finns kvar.");return NO;}
 AVMutableComposition *composition=[AVMutableComposition composition];NSError *error=nil;
 AVMutableCompositionTrack *vt=[composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];if(![vt insertTimeRange:v.timeRange ofTrack:v atTime:v.timeRange.start error:&error])return NO;
 NSDictionary *videoTime=timingFile([directory stringByAppendingPathComponent:@"video-timing.json"]),*audioTime=timingFile([directory stringByAppendingPathComponent:@"audio-timing.json"]);
 BOOL audioIncluded=NO;
 if(a&&[audioTime[@"first_host_seconds"] doubleValue]>0&&videoTime){double offset=[audioTime[@"first_host_seconds"] doubleValue]-[videoTime[@"epoch"] doubleValue];CMTime skip=CMTimeMakeWithSeconds(MAX(0,-offset),1000000);CMTime at=CMTimeMakeWithSeconds(MAX(0,offset),1000000);CMTime duration=CMTimeMinimum(CMTimeSubtract(a.timeRange.duration,skip),CMTimeSubtract(CMTimeRangeGetEnd(v.timeRange),at));if(CMTimeCompare(duration,kCMTimeZero)>0){AVMutableCompositionTrack *atc=[composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];if(![atc insertTimeRange:CMTimeRangeMake(skip,duration) ofTrack:a atTime:at error:&error])return NO;audioIncluded=YES;}}
 else {puts("Ljud eller dess tidsstämpel saknas. Sparar video utan ljud; WAV finns kvar om den skapades.");}
 AVAssetExportSession *exporter=[[AVAssetExportSession alloc]initWithAsset:composition presetName:AVAssetExportPresetPassthrough];exporter.outputURL=[NSURL fileURLWithPath:output];exporter.outputFileType=AVFileTypeQuickTimeMovie;
 dispatch_semaphore_t done=dispatch_semaphore_create(0);[exporter exportAsynchronouslyWithCompletionHandler:^{dispatch_semaphore_signal(done);}];
 if(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,300*NSEC_PER_SEC))||exporter.status!=AVAssetExportSessionStatusCompleted){[exporter cancelExport];puts(exporter.error.description.UTF8String?:"Sammanfogningen misslyckades.");return NO;}
 NSData *report=[NSJSONSerialization dataWithJSONObject:@{@"audio_included":@(audioIncluded),@"sync":@"host start alignment; drift not verified"} options:0 error:NULL];[report writeToFile:[directory stringByAppendingPathComponent:@"mux-report.json"] atomically:YES];return YES;
}
