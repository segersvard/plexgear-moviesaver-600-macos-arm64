CC = xcrun clang
CFLAGS = -arch arm64 -Wall -Wextra -Werror -Isrc
FRAMEWORKS = -framework Foundation -framework AppKit -framework IOKit -framework IOUSBHost -framework AVFoundation -framework CoreAudio -framework AudioToolbox

.PHONY: all test replay clean
all: build/plexgear-pal build/make-jpeg

build:
	mkdir -p build

build/field_parser.o: src/field_parser.c src/field_parser.h | build
	$(CC) $(CFLAGS) -std=c11 -c $< -o $@

build/plexgear-pal: src/plexgear-pal.m src/audio_capture.m src/audio_capture.h src/Info.plist build/field_parser.o
	$(CC) $(CFLAGS) -fobjc-arc -fblocks $(FRAMEWORKS) -Wl,-sectcreate,__TEXT,__info_plist,src/Info.plist src/plexgear-pal.m src/audio_capture.m build/field_parser.o -o $@

build/test-parser: src/field_parser.c src/field_parser.h tests/test_parser.c | build
	$(CC) $(CFLAGS) -std=c11 src/field_parser.c tests/test_parser.c -o $@

build/test-real-capture: src/field_parser.c src/field_parser.h tests/test_real_capture.c | build
	$(CC) $(CFLAGS) -std=c11 src/field_parser.c tests/test_real_capture.c -o $@

build/make-jpeg: tools/make-jpeg.m | build
	$(CC) $(CFLAGS) -fobjc-arc -framework Foundation -framework AppKit $< -o $@

test: build/test-parser
	./build/test-parser

replay: build/test-real-capture
	@test -n "$(CAPTURE)" || (echo 'Usage: make replay CAPTURE=/absolute/path/to/capture'; exit 1)
	./build/test-real-capture "$(CAPTURE)/videopaket.tsv" "$(CAPTURE)/video-usb.bin"

clean:
	rm -rf build
