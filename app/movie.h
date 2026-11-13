// SPDX-License-Identifier: GPL-2.0-or-later
#import <Foundation/Foundation.h>
@interface PGMovie:NSObject
@property(readonly) BOOL failed;
/* Skapar en begränsad skrivkö för målmappen och en gemensam värdtid; returnerar objekt eller nil. */
-(instancetype)initWithDirectory:(NSString *)directory epoch:(double)epoch;
/* Sätter värdtidens origo innan första fältet köas; tar sekunder och returnerar inget. */
-(void)setEpoch:(double)epoch;
/* Köar ett PAL-fält med hårdvaruräknare och värdtid; returnerar inget och tappar hellre bild än bygger obegränsad kö. */
-(void)field:(const uint8_t *)bytes counter:(uint8_t)counter time:(double)time;
/* Tömmer skrivkön och slutför videospåret; returnerar om filmen kunde stängas. */
-(BOOL)finish;
@end
/* Sammanfogar färdiga video- och ljudfiler med uppmätt startförskjutning; returnerar status utan att radera delmaterial. */
BOOL pg_mux(NSString *directory,NSString *output);
