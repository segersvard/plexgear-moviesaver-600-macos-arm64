// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
/* Begränsar en färgkanal till en byte; tar heltal och returnerar kanalvärdet. */
static uint8_t clip(int v){return v<0?0:v>255?255:v;}
/* Omvandlar 720x576 YUYV-bilder till 768x576 JPEG för 4:3; tar råfil och utmapp och returnerar status. */
int main(int argc,const char *argv[]){@autoreleasepool{
 if(argc!=3)return 1;NSData *data=[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];if(!data.length||data.length%(720*576*2))return 2;
 NSUInteger count=data.length/(720*576*2);NSString *dir=[NSString stringWithUTF8String:argv[2]];[[NSFileManager defaultManager]createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
 for(NSUInteger index=0;index<count;index++){@autoreleasepool{
 NSBitmapImageRep *image=[[NSBitmapImageRep alloc]initWithBitmapDataPlanes:NULL pixelsWide:768 pixelsHigh:576 bitsPerSample:8 samplesPerPixel:3 hasAlpha:NO isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:768*3 bitsPerPixel:24];if(!image)return 3;
 const uint8_t *src=(const uint8_t *)data.bytes+index*720*576*2;uint8_t *dst=image.bitmapData;
 for(int y=0;y<576;y++)for(int x=0;x<768;x++){int sx=x*720/768;size_t p=((size_t)y*720+(sx&~1))*2;int c=src[p+(sx&1)*2]-16,u=src[p+1]-128,v=src[p+3]-128;size_t d=((size_t)y*768+x)*3;dst[d]=clip((298*c+409*v+128)>>8);dst[d+1]=clip((298*c-100*u-208*v+128)>>8);dst[d+2]=clip((298*c+516*u+128)>>8);}
 if(![[image representationUsingType:NSBitmapImageFileTypeJPEG properties:@{NSImageCompressionFactor:@0.92}]writeToFile:[dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%04lu.jpg",(unsigned long)index]] atomically:YES])return 4;
 }}return 0;
}}
