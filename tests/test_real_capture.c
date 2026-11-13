/* SPDX-License-Identifier: MIT */
#include "field_parser.h"
#include <stdio.h>
#include <stdlib.h>
/* Kör parsern på en sparad paketlogg och dess rådata; tar TSV och BIN och returnerar status. */
int main(int argc,char **argv){if(argc!=3)return 1;FILE *log=fopen(argv[1],"r"),*raw=fopen(argv[2],"rb");if(!log||!raw)return 2;PGFieldParser *p=calloc(1,sizeof(*p));if(!p)return 3;pg_init(p,NULL,NULL);char line[1024];uint8_t data[3072];fgets(line,sizeof(line),log);while(fgets(line,sizeof(line),log)){unsigned long long frame,offset;unsigned micro,status;size_t n;if(sscanf(line,"%llu\t%u\t%x\t%zu\t%llu",&frame,&micro,&status,&n,&offset)!=5)return 4;if(n>sizeof(data)||fseek(raw,(long)offset,SEEK_SET)||fread(data,1,n,raw)!=n)return 5;pg_feed(p,data,n,status==0);}printf("headers=%llu complete=%llu rejected=%llu dropped=%llu\n",(unsigned long long)p->headers,(unsigned long long)p->complete,(unsigned long long)p->rejected,(unsigned long long)p->dropped);free(p);fclose(log);fclose(raw);return 0;}
