// SPDX-License-Identifier: MIT
#import <Foundation/Foundation.h>
typedef struct PGAudio PGAudio;
/* Begär vid behov macOS ljudbehörighet innan USB initieras; returnerar om ljudinspelning får provas. */
BOOL pg_audio_permission(void);
/* Väljer endast en USB 2828x-ljudingång och börjar skriva WAV i mappen; returnerar kontext eller NULL. */
PGAudio *pg_audio_start(NSString *directory);
/* Stoppar och stänger ljudinspelningen, skriver statistik och frigör kontexten; returnerar om ljudprover sparats utan fil- eller köfel. */
BOOL pg_audio_stop(PGAudio *capture);
