/* SPDX-License-Identifier: MIT */
#ifndef FIELD_PARSER_H
#define FIELD_PARSER_H
#include <stddef.h>
#include <stdint.h>
enum { PG_WIDTH=720, PG_FIELD_HEIGHT=288, PG_FIELD_BYTES=720*288*2, PG_FIELD_STORAGE_BYTES=720*288*2+4 };
typedef void (*PGFieldCallback)(const uint8_t *,size_t,int,void *);
typedef struct {
    uint8_t data[PG_FIELD_STORAGE_BYTES];size_t length;
    int active,parity;
    uint64_t headers,complete,rejected,dropped,vbi;
    PGFieldCallback callback;void *context;
} PGFieldParser;
/* Initierar en parser med callback och kontext; returnerar inget. */
void pg_init(PGFieldParser *p,PGFieldCallback callback,void *context);
/* Tar ett avslutat USB-paket och status; samlar endast exakta PAL-fält och returnerar inget. */
void pg_feed(PGFieldParser *p,const uint8_t *data,size_t length,int success);
#endif
