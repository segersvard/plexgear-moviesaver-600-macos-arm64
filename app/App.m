// SPDX-License-Identifier: GPL-2.0-or-later
#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <signal.h>
@interface RecorderApp:NSObject<NSApplicationDelegate,NSWindowDelegate>
@property NSWindow *window;
@property NSImageView *preview;
@property NSTextField *status,*details;
@property NSButton *start,*stop,*show;
@property NSTask *task;
@property NSFileHandle *log;
@property NSTimer *timer;
@property NSString *work,*destination;
@property NSDate *began;
@property BOOL stopping;
@end
@implementation RecorderApp
/* Skapar ett enkelt inspelningsfönster utan USB-åtkomst vid start; tar startnotis och returnerar inget. */
-(void)applicationDidFinishLaunching:(NSNotification *)note{
 (void)note;self.window=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,820,680) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];self.window.title=@"Moviesaver 600 – Inspelning";self.window.delegate=self;
 NSView *view=self.window.contentView;
 NSTextField *title=[NSTextField labelWithString:@"Spela in från VHS eller annan PAL-källa"];title.font=[NSFont boldSystemFontOfSize:21];title.frame=NSMakeRect(26,628,770,30);[view addSubview:title];
 NSTextField *intro=[NSTextField labelWithString:@"Plexgear Moviesaver 600 · PAL 576i · Komposit · Stereo · Apple Silicon"];intro.frame=NSMakeRect(26,596,770,22);intro.textColor=NSColor.secondaryLabelColor;[view addSubview:intro];
 self.preview=[[NSImageView alloc]initWithFrame:NSMakeRect(26,148,768,432)];self.preview.imageScaling=NSImageScaleProportionallyUpOrDown;self.preview.wantsLayer=YES;self.preview.layer.backgroundColor=NSColor.blackColor.CGColor;[view addSubview:self.preview];
 self.status=[NSTextField labelWithString:@"Klar. Anslut gul bildkontakt och röd/vit ljudkontakt."];self.status.frame=NSMakeRect(26,110,770,26);[view addSubview:self.status];
 self.details=[NSTextField labelWithString:@"Bilden visas under inspelningen. Film sparas som MOV. Första versionen är experimentell."];self.details.frame=NSMakeRect(26,82,770,23);self.details.font=[NSFont systemFontOfSize:12];self.details.textColor=NSColor.secondaryLabelColor;[view addSubview:self.details];
 self.start=[NSButton buttonWithTitle:@"Spela in…" target:self action:@selector(startRecording:)];self.start.frame=NSMakeRect(26,27,150,36);self.start.bezelStyle=NSBezelStyleRounded;[view addSubview:self.start];
 self.stop=[NSButton buttonWithTitle:@"Stoppa och spara" target:self action:@selector(stopRecording:)];self.stop.frame=NSMakeRect(184,27,180,36);self.stop.enabled=NO;[view addSubview:self.stop];
 self.show=[NSButton buttonWithTitle:@"Visa filerna" target:self action:@selector(showFiles:)];self.show.frame=NSMakeRect(618,27,176,36);self.show.enabled=NO;[view addSubview:self.show];
 NSMenu *menu=[NSMenu new];NSMenuItem *root=[NSMenuItem new];[menu addItem:root];NSMenu *appMenu=[NSMenu new];[appMenu addItemWithTitle:@"Avsluta Moviesaver" action:@selector(terminate:) keyEquivalent:@"q"];root.submenu=appMenu;NSApp.mainMenu=menu;
 [self.window center];[self.window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];
}
/* Visar fel i en dialog utan att ta bort inspelade filer; tar meddelande och returnerar inget. */
-(void)problem:(NSString *)text{NSAlert *alert=[NSAlert new];alert.messageText=@"Inspelningen kunde inte slutföras";alert.informativeText=text;[alert runModal];}
/* Begär ljudbehörighet och väljer en ny filmfil; tar knappavsändare och returnerar inget. */
-(void)startRecording:(id)sender{
 (void)sender;if(self.task.running)return;NSSavePanel *panel=[NSSavePanel savePanel];panel.allowedContentTypes=@[UTTypeQuickTimeMovie];NSDateFormatter *format=[NSDateFormatter new];format.dateFormat=@"yyyy-MM-dd_HHmmss";panel.nameFieldStringValue=[NSString stringWithFormat:@"Inspelning-%@.mov",[format stringFromDate:NSDate.date]];
 if([panel runModal]!=NSModalResponseOK)return;if([[NSFileManager defaultManager]fileExistsAtPath:panel.URL.path]){[self problem:@"Välj ett nytt filnamn. Befintliga filmer skrivs inte över."];return;}self.destination=panel.URL.path;
 self.start.enabled=NO;self.show.enabled=NO;self.status.stringValue=@"Kontrollerar ljudbehörighet…";
 [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted){dispatch_async(dispatch_get_main_queue(),^{if(!granted){self.start.enabled=YES;self.status.stringValue=@"Ljudbehörighet saknas. Tillåt appen i Systeminställningar → Integritet och säkerhet → Mikrofon.";return;}[self launchRecorder];});}];
}
/* Startar den inbyggda ARM64-motorn och tidsuppdateringar; tar inga argument och returnerar inget. */
-(void)launchRecorder{
 self.work=[self.destination stringByAppendingFormat:@".delmaterial-%@",[[NSUUID UUID].UUIDString substringToIndex:8]];NSError *error=nil;
 if(![[NSFileManager defaultManager]createDirectoryAtPath:self.work withIntermediateDirectories:NO attributes:nil error:&error]){self.start.enabled=YES;[self problem:error.localizedDescription];return;}
 NSString *logPath=[self.work stringByAppendingPathComponent:@"inspelning.log"];[[NSFileManager defaultManager]createFileAtPath:logPath contents:nil attributes:nil];self.log=[NSFileHandle fileHandleForWritingAtPath:logPath];
 self.task=[NSTask new];self.task.executableURL=[NSURL fileURLWithPath:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Contents/MacOS/recorder"]];self.task.arguments=@[self.work,self.destination];self.task.standardOutput=self.log;self.task.standardError=self.log;self.stopping=NO;
 __weak RecorderApp *weakSelf=self;self.task.terminationHandler=^(NSTask *task){int code=task.terminationStatus;dispatch_async(dispatch_get_main_queue(),^{[weakSelf completed:code];});};
 if(![self.task launchAndReturnError:&error]){self.start.enabled=YES;[self.log closeFile];[self problem:error.localizedDescription];return;}
 self.began=NSDate.date;self.stop.enabled=YES;self.status.stringValue=@"Startar digitaliseraren…";self.details.stringValue=@"Stoppa med knappen för att spara. Max fyra timmar. Kontrollera bild och ljud med ett kort prov först.";self.timer=[NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(update:) userInfo:nil repeats:YES];
}
/* Uppdaterar förhandsbild och förfluten tid utan att läsa USB; tar timer och returnerar inget. */
-(void)update:(NSTimer *)timer{
 (void)timer;NSInteger seconds=(NSInteger)-self.began.timeIntervalSinceNow;NSString *path=[self.work stringByAppendingPathComponent:@"preview.jpg"];NSImage *image=[[NSImage alloc]initWithContentsOfFile:path];if(image)self.preview.image=image;
 if(!self.stopping)self.status.stringValue=[NSString stringWithFormat:@"%@ · %02ld:%02ld:%02ld",image?@"Spelar in":@"Väntar på komplett PAL-bild",(long)(seconds/3600),(long)((seconds/60)%60),(long)(seconds%60)];
}
/* Begär ordnad avslutning med SIGINT och väntar på färdig fil; tar knapp och returnerar inget. */
-(void)stopRecording:(id)sender{(void)sender;if(!self.task.running||self.stopping)return;self.stopping=YES;self.stop.enabled=NO;self.status.stringValue=@"Stoppar och sparar filmen… Stäng inte appen ännu.";kill(self.task.processIdentifier,SIGINT);}
/* Visar verifierad filstatus efter att motorn avslutats; tar slutkod och returnerar inget. */
-(void)completed:(int)code{
 [self.timer invalidate];self.timer=nil;[self.log closeFile];self.log=nil;self.start.enabled=YES;self.stop.enabled=NO;self.show.enabled=YES;
 BOOL exists=(code==0||code==6||code==8)&&[[NSFileManager defaultManager]fileExistsAtPath:self.destination];self.status.stringValue=exists?(code==0?@"Filmen är sparad.":@"Filmen sparades med varningar. Kontrollera bild, ljud och logg."):@"Ingen färdig film skapades. Delmaterial och logg finns kvar.";
 self.details.stringValue=@"Visa filerna och importera MOV-filen i ditt redigeringsprogram. Delmaterialet behålls tills du själv tar bort det.";
 if(!exists)[self problem:[NSString stringWithFormat:@"Slutkod %d. Öppna Visa filerna för delmaterial och inspelning.log. Koppla ur och återanslut digitaliseraren innan nästa försök om USB har slutat svara.",code]];
}
/* Öppnar den färdiga filmen eller arbetsmappen i Finder; tar knapp och returnerar inget. */
-(void)showFiles:(id)sender{(void)sender;NSString *path=[[NSFileManager defaultManager]fileExistsAtPath:self.destination]?self.destination:self.work;[NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:path]]];}
/* Hindrar stängning medan filmen sparas; tar fönster och returnerar om det får stängas. */
-(BOOL)windowShouldClose:(NSWindow *)window{(void)window;if(self.task.running){[self stopRecording:nil];return NO;}[NSApp terminate:nil];return YES;}
/* Begär stopp vid Avsluta och låter användaren avsluta efter att filen stängts; returnerar beslut. */
-(NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender{(void)sender;if(self.task.running){[self stopRecording:nil];return NSTerminateCancel;}return NSTerminateNow;}
@end
/* Startar AppKit-appen med en kvarhållen delegat; tar processargument och returnerar status. */
int main(int argc,const char *argv[]){(void)argc;(void)argv;@autoreleasepool{[NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];RecorderApp *delegate=[RecorderApp new];NSApp.delegate=delegate;[NSApp run];}return 0;}
