// SPDX-License-Identifier: MIT
#import "audio_capture.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreAudio/CoreAudio.h>
#import <AudioToolbox/AudioToolbox.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
static NSString *pgTimingDirectory;
struct PGAudio {AudioQueueRef queue;AudioFileID file;atomic_bool running;SInt64 packets;uint64_t samples;double squareSum;int peak;OSStatus error;double firstHostSeconds;};

/* Kontrollerar ljudbehörighet och låter macOS visa sin dialog vid behov; tar inga argument och returnerar status. */
BOOL pg_audio_permission(void){
    AVAuthorizationStatus status=[AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    if(status==AVAuthorizationStatusAuthorized)return YES;
    if(status==AVAuthorizationStatusDenied||status==AVAuthorizationStatusRestricted){puts("Ljudbehörighet saknas. Videotestet kan ändå fortsätta.");return NO;}
    puts("macOS kan nu fråga om ljudingång/mikrofon. Tillåt för att testa digitaliserarens ljud.");
    dispatch_semaphore_t ready=dispatch_semaphore_create(0);__block BOOL granted=NO;
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL allowed){granted=allowed;dispatch_semaphore_signal(ready);}];
    NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:45];
    while(dispatch_semaphore_wait(ready,DISPATCH_TIME_NOW)!=0){if(limit.timeIntervalSinceNow<=0){puts("Ingen ljudbehörighet bekräftad inom 45 sekunder. Fortsätter med video.");return NO;}[[NSRunLoop currentRunLoop]runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];}
    return granted;
}

/* Söker CoreAudio-enheter med ingång och identifieraren 2828; returnerar en ägd UID eller NULL. Ingen standardmikrofon väljs. */
static CFStringRef findUSBInput(void){
    AudioObjectPropertyAddress address={kAudioHardwarePropertyDevices,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};UInt32 bytes=0;
    if(AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,&address,0,NULL,&bytes)!=noErr||!bytes)return NULL;
    AudioDeviceID *devices=malloc(bytes);if(!devices)return NULL;
    if(AudioObjectGetPropertyData(kAudioObjectSystemObject,&address,0,NULL,&bytes,devices)!=noErr){free(devices);return NULL;}
    CFStringRef chosen=NULL;
    for(size_t i=0;i<bytes/sizeof(AudioDeviceID);i++){
        AudioObjectPropertyAddress streams={kAudioDevicePropertyStreams,kAudioDevicePropertyScopeInput,kAudioObjectPropertyElementMain};UInt32 streamBytes=0;
        if(AudioObjectGetPropertyDataSize(devices[i],&streams,0,NULL,&streamBytes)!=noErr||!streamBytes)continue;
        CFStringRef cfName=NULL,uid=NULL;UInt32 size=sizeof(cfName);AudioObjectPropertyAddress name={kAudioObjectPropertyName,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
        if(AudioObjectGetPropertyData(devices[i],&name,0,NULL,&size,&cfName)!=noErr)continue;
        AudioObjectPropertyAddress uidAddress={kAudioDevicePropertyDeviceUID,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};size=sizeof(uid);
        if(AudioObjectGetPropertyData(devices[i],&uidAddress,0,NULL,&size,&uid)!=noErr){if(cfName)CFRelease(cfName);continue;}
        NSString *text=[NSString stringWithFormat:@"%@ %@",(__bridge NSString *)cfName,(__bridge NSString *)uid];
        printf("Ljudingång: %s\n",((__bridge NSString *)cfName).UTF8String);
        if([text rangeOfString:@"2828" options:NSCaseInsensitiveSearch].location!=NSNotFound){chosen=uid;if(cfName)CFRelease(cfName);break;}
        if(cfName)CFRelease(cfName);if(uid)CFRelease(uid);
    }
    free(devices);return chosen;
}

/* Skriver ett PCM-ljudblock till WAV och återköar bufferten; tar AudioQueue-argument och returnerar inget. */
static void audioInput(void *context,AudioQueueRef queue,AudioQueueBufferRef buffer,const AudioTimeStamp *time,UInt32 packetCount,const AudioStreamPacketDescription *descriptions){
    (void)packetCount;(void)descriptions;PGAudio *a=context;if(!atomic_load(&a->running))return;
    UInt32 count=buffer->mAudioDataByteSize/4;
    if(buffer->mAudioDataByteSize%4){a->error=kAudio_ParamError;return;}
    if(count){
        if(!a->packets&&time&&(time->mFlags&kAudioTimeStampHostTimeValid))a->firstHostSeconds=AudioConvertHostTimeToNanos(time->mHostTime)/1e9;
        OSStatus status=AudioFileWritePackets(a->file,false,buffer->mAudioDataByteSize,NULL,a->packets,&count,buffer->mAudioData);
        if(status!=noErr){a->error=status;return;}a->packets+=count;
        const int16_t *samples=buffer->mAudioData;size_t n=(size_t)count*2;
        for(size_t i=0;i<n;i++){int value=samples[i];int magnitude=value<0?-value:value;if(magnitude>a->peak)a->peak=magnitude;a->squareSum+=(double)value*value;}a->samples+=n;
    }
    if(atomic_load(&a->running)){OSStatus status=AudioQueueEnqueueBuffer(queue,buffer,0,NULL);if(status!=noErr)a->error=status;}
}

/* Skapar stereo 48 kHz/16-bit WAV från den identifierade USB-ljudingången; tar målmapppen och returnerar kontext eller NULL. */
PGAudio *pg_audio_start(NSString *directory){
    pgTimingDirectory=[directory copy];
    CFStringRef uid=findUSBInput();if(!uid){puts("Ingen USB 2828x-ljudingång hittades. Ingen annan mikrofon spelas in.");return NULL;}
    PGAudio *a=calloc(1,sizeof(*a));if(!a){CFRelease(uid);return NULL;}atomic_init(&a->running,false);
    AudioStreamBasicDescription format={0};format.mSampleRate=48000;format.mFormatID=kAudioFormatLinearPCM;format.mFormatFlags=kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsPacked;format.mBytesPerPacket=4;format.mFramesPerPacket=1;format.mBytesPerFrame=4;format.mChannelsPerFrame=2;format.mBitsPerChannel=16;
    OSStatus status=AudioQueueNewInput(&format,audioInput,a,NULL,NULL,0,&a->queue);
    if(status==noErr)status=AudioQueueSetProperty(a->queue,kAudioQueueProperty_CurrentDevice,&uid,sizeof(uid));
    CFRelease(uid);
    if(status==noErr){NSURL *url=[NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"wiiu-ljud.wav"]];status=AudioFileCreateWithURL((__bridge CFURLRef)url,kAudioFileWAVEType,&format,kAudioFileFlags_EraseFile,&a->file);}
    for(int i=0;i<3&&status==noErr;i++){AudioQueueBufferRef b=NULL;status=AudioQueueAllocateBuffer(a->queue,4800*4,&b);if(status==noErr)status=AudioQueueEnqueueBuffer(a->queue,b,0,NULL);}
    if(status==noErr){atomic_store(&a->running,true);status=AudioQueueStart(a->queue,NULL);}
    if(status!=noErr){printf("USB-ljud kunde inte starta: OSStatus %d.\n",(int)status);atomic_store(&a->running,false);if(a->queue)AudioQueueDispose(a->queue,true);if(a->file)AudioFileClose(a->file);free(a);return NULL;}
    puts("USB-ljud startat: WAV, stereo, 48 kHz, 16 bit. Ingen dator-mikrofon används.");return a;
}

/* Stoppar AudioQueue innan statistik läses och stänger WAV; tar kontext och returnerar om ljudprover sparats utan fil- eller köfel. */
BOOL pg_audio_stop(PGAudio *a){
    if(!a)return NO;atomic_store(&a->running,false);OSStatus stop=AudioQueueStop(a->queue,true);AudioQueueDispose(a->queue,true);OSStatus close=AudioFileClose(a->file);
    double rms=a->samples?sqrt(a->squareSum/a->samples)/32768.0:0;
    printf("Ljud: %.3f s, topp %.2f %% av full skala, RMS %.4f, callbackfel=%d, stopp=%d, filstängning=%d.\n",a->packets/48000.0,a->peak*100.0/32768.0,rms,(int)a->error,(int)stop,(int)close);
    NSData *timing=[NSJSONSerialization dataWithJSONObject:@{@"first_host_seconds":@(a->firstHostSeconds),@"sample_frames":@(a->packets)} options:0 error:NULL];[timing writeToFile:[pgTimingDirectory stringByAppendingPathComponent:@"audio-timing.json"] atomically:YES];
    BOOL success=a->samples>0&&a->error==noErr&&stop==noErr&&close==noErr;
    puts(success?"Ljudprover sparade. Även tyst ljud är giltigt; lyssna på WAV-filen för att verifiera källan.":"USB-källljud är inte verifierat; kontrollera rapporten och WAV-filen.");free(a);return success;
}
