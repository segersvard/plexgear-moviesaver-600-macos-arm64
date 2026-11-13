/* SPDX-License-Identifier: MIT */
#include "field_parser.h"
#include <string.h>
/* Nollställer parsern och installerar callbacken; tar parser, funktion och kontext och returnerar inget. */
void pg_init(PGFieldParser *p,PGFieldCallback callback,void *context){memset(p,0,sizeof(*p));p->callback=callback;p->context=context;}
/* Avslutar endast ett fält som avgränsats av ett nytt huvud; tar parsern och returnerar inget. */
static void finish(PGFieldParser *p){
    if(!p->active)return;
    const uint8_t trailer[]={0xc6,0x93,0x05,0x93};
    int exact=p->length==PG_FIELD_BYTES;
    int withTrailer=p->length==PG_FIELD_STORAGE_BYTES && memcmp(p->data+PG_FIELD_BYTES,trailer,4)==0;
    if(exact||withTrailer){p->complete++;if(p->callback)p->callback(p->data,PG_FIELD_BYTES,p->parity,p->context);}
    else p->rejected++;
}
/* Tolkar ett paket med oförstörda gränser; tar parser, bytes, längd och USB-status och returnerar inget. */
void pg_feed(PGFieldParser *p,const uint8_t *data,size_t length,int success){
    if(!success){if(p->active)p->rejected++;p->dropped++;p->active=0;p->length=0;return;}
    if(length>=4&&data[0]==0x22&&data[1]==0x5a){finish(p);p->headers++;p->parity=data[2]&1;p->active=1;p->length=0;data+=4;length-=4;}
    else if(length>=4&&data[0]==0x33&&data[1]==0x95){finish(p);p->vbi++;p->active=0;p->length=0;return;}
    else if(length>=4&&data[0]==0x88&&data[1]==0x88&&data[2]==0x88&&data[3]==0x88){data+=4;length-=4;}
    if(!p->active||!length)return;
    if(length>PG_FIELD_STORAGE_BYTES-p->length){p->rejected++;p->active=0;p->length=0;return;}
    memcpy(p->data+p->length,data,length);p->length+=length;
}
