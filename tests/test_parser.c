/* SPDX-License-Identifier: MIT */
#include "field_parser.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static int callbacks=0;
/* Verifierar innehåll och fältparitet i testcallback; tar fält och kontext och returnerar inget. */
static void received(const uint8_t *data,size_t length,int parity,void *context){(void)context;assert(length==PG_FIELD_BYTES);assert(parity==0);for(size_t i=0;i<length;i++)assert(data[i]==0x80);callbacks++;}
/* Provar paketgränser, avbrott, fel och längdgränser utan USB; tar inga argument och returnerar status. */
int main(void){
    PGFieldParser *p=calloc(1,sizeof(*p));uint8_t *field=malloc(PG_FIELD_STORAGE_BYTES+1);assert(p&&field);memset(field,0x80,PG_FIELD_STORAGE_BYTES+1);
    const uint8_t h[]={0x22,0x5a,0,0},v[]={0x33,0x95,0,0},cont[]={0x88,0x88,0x88,0x88};
    pg_init(p,received,NULL);pg_feed(p,field,100,1);assert(!p->active);
    pg_feed(p,h,4,1);pg_feed(p,field,100000,1);pg_feed(p,cont,4,1);pg_feed(p,field+100000,PG_FIELD_BYTES-100000,1);
    assert(p->complete==0);pg_feed(p,h,4,1);assert(p->complete==1&&callbacks==1);
    pg_feed(p,field,100,1);pg_feed(p,h,4,1);assert(p->rejected==1);
    pg_feed(p,field,PG_FIELD_STORAGE_BYTES+1,1);assert(!p->active&&p->rejected==2);
    pg_feed(p,h,4,1);pg_feed(p,field,100,1);pg_feed(p,NULL,0,0);assert(p->dropped==1&&!p->active);
    pg_feed(p,field,PG_FIELD_BYTES,1);assert(p->complete==1);
    pg_feed(p,h,4,1);pg_feed(p,v,4,1);assert(p->vbi==1&&!p->active);
    pg_feed(p,h,4,1);pg_feed(p,field,PG_FIELD_BYTES,1);assert(p->complete==1); // Oavslutat sista fält räknas inte.
    pg_init(p,received,NULL);pg_feed(p,h,4,1);pg_feed(p,field,PG_FIELD_BYTES,1);
    const uint8_t trailer[]={0xc6,0x93,0x05,0x93};pg_feed(p,trailer,4,1);pg_feed(p,h,4,1);assert(p->complete==1);
    pg_feed(p,field,PG_FIELD_BYTES,1);const uint8_t bad[]={1,2,3,4};pg_feed(p,bad,4,1);pg_feed(p,h,4,1);assert(p->complete==1&&p->rejected==1);
    free(field);free(p);puts("Parser OK: paketgränser, fortsättningshuvuden, längder, USB-fel och oavslutade fält.");return 0;
}
