/*
 * Copyright 2001  Brian S. Dean <bsd@bsdhome.com>
 * All Rights Reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY BRIAN S. DEAN ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL BRIAN S. DEAN BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
 * OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
 * BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE
 * USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
 * DAMAGE.
 * 
 */

/* $Id$ */

%token K_BANK_SIZE
%token K_BANKED
%token K_BUFF
%token K_CHIP_ERASE_DELAY
%token K_DESC
%token K_EEPROM
%token K_ERRLED
%token K_FLASH
%token K_ID
%token K_MAX_WRITE_DELAY
%token K_MIN_WRITE_DELAY
%token K_MISO
%token K_MOSI
%token K_NO
%token K_NUM_BANKS
%token K_PART
%token K_PGMLED
%token K_PROGRAMMER
%token K_RDYLED
%token K_READBACK_P1
%token K_READBACK_P2
%token K_RESET
%token K_SCK
%token K_SIZE
%token K_VCC
%token K_VFYLED
%token K_YES

%token TKN_COMMA
%token TKN_EQUAL
%token TKN_SEMI
%token TKN_NUMBER
%token TKN_STRING
%token TKN_ID

%start config

%%


config :
  def |
  config def
;


def :
  prog_def TKN_SEMI |
  part_def TKN_SEMI
;


prog_def :
  K_PROGRAMMER 
    { current_prog = new_programmer(); }
    prog_parms
    { 
      if (lsize(current_prog->id) == 0) {
        fprintf(stderr,
                "%s: error at %s:%d: required parameter id not specified\n",
                progname, infile, lineno);
        exit(1);
      }
      ladd(programmers, current_prog); 
      current_prog = NULL; 
    }
;


part_def :
  K_PART
    { current_part = avr_new_part(); }
    part_parms 
    { 
      unsigned int i, j, pagebits;
      if (current_part->id[0] == 0) {
        fprintf(stderr,
                "%s: error at %s:%d: required parameter id not specified\n",
                progname, infile, lineno);
        exit(1);
      }

      /*
       * perform some sanity checking
       */
      for (i=0; i<AVR_MAXMEMTYPES; i++) {
        if (current_part->mem[i].banked) {
          if (!current_part->mem[i].bank_size) {
            fprintf(stderr, 
                    "%s: error at %s:%d: must specify bank_size for banked "
                    "memory\n",
                    progname, infile, lineno);
            exit(1);
          }
          if (!current_part->mem[i].num_banks) {
            fprintf(stderr, 
                    "%s: error at %s:%d: must specify num_banks for banked "
                    "memory\n",
                    progname, infile, lineno);
            exit(1);
          }
          if (current_part->mem[i].size != current_part->mem[i].bank_size *
                                             current_part->mem[i].num_banks) {
            fprintf(stderr, 
                    "%s: error at %s:%d: bank size (%u) * num_banks (%u) = "
                    "%u does not match memory size (%u)\n",
                    progname, infile, lineno,
                    current_part->mem[i].bank_size, 
                    current_part->mem[i].num_banks, 
                    current_part->mem[i].bank_size * current_part->mem[i].num_banks,
                    current_part->mem[i].size);
            exit(1);
          }
          pagebits = 0;
          for (j=0; j<32 && !pagebits; j++) {
            if ((1 << j) == current_part->mem[i].num_banks)
              pagebits = j;
          }
          if (!pagebits) {
            fprintf(stderr, 
                    "%s: error at %s:%d: can't determine the number of bank address bits\n"
                    "     Are you sure num_banks (=%u) is correct?\n",
                    progname, infile, lineno, current_part->mem[i].num_banks);
            exit(1);
          }
          current_part->mem[i].bankaddrbits = pagebits;
        }
      }

      ladd(part_list, current_part); 
      current_part = NULL; 
    }
;


string_list :
  TKN_STRING { ladd(string_list, $1); } |
  string_list TKN_COMMA TKN_STRING { ladd(string_list, $3); }
;


num_list :
  TKN_NUMBER { ladd(number_list, $1); } |
  num_list TKN_COMMA TKN_NUMBER { ladd(number_list, $3); }
;


prog_parms :
  prog_parm TKN_SEMI |
  prog_parms prog_parm TKN_SEMI
;


prog_parm :
  K_ID TKN_EQUAL string_list {
    { 
      TOKEN * t;
      while (lsize(string_list)) {
        t = lrmv_n(string_list, 1);
        ladd(current_prog->id, dup_string(t->value.string));
        free_token(t);
      }
    }
  } |

  K_DESC TKN_EQUAL TKN_STRING {
    strncpy(current_prog->desc, $3->value.string, PGM_DESCLEN);
    current_prog->desc[PGM_DESCLEN-1] = 0;
    free_token($3);
  } |

  K_VCC TKN_EQUAL num_list {
    { 
      TOKEN * t;
      int pin;

      current_prog->pinno[PPI_AVR_VCC] = 0;

      while (lsize(number_list)) {
        t = lrmv_n(number_list, 1);
        pin = t->value.number;
        if ((pin < 2) || (pin > 9)) {
          fprintf(stderr, 
                  "%s: error at line %d of %s: VCC must be one or more "
                  "pins from the range 2-9\n",
                  progname, lineno, infile);
          exit(1);
        }

        current_prog->pinno[PPI_AVR_VCC] |= (1 << (pin-2));

        free_token(t);
      }
    }
  } |

  K_RESET  TKN_EQUAL TKN_NUMBER { assign_pin(PIN_AVR_RESET, $3); } |
  K_SCK    TKN_EQUAL TKN_NUMBER { assign_pin(PIN_AVR_SCK, $3); } |
  K_MOSI   TKN_EQUAL TKN_NUMBER { assign_pin(PIN_AVR_MOSI, $3); } |
  K_MISO   TKN_EQUAL TKN_NUMBER { assign_pin(PIN_AVR_MISO, $3); } |
  K_BUFF   TKN_EQUAL TKN_NUMBER { assign_pin(PIN_AVR_BUFF, $3); } |
  K_ERRLED TKN_EQUAL TKN_NUMBER { assign_pin(PIN_LED_ERR, $3); } |
  K_RDYLED TKN_EQUAL TKN_NUMBER { assign_pin(PIN_LED_RDY, $3); } |
  K_PGMLED TKN_EQUAL TKN_NUMBER { assign_pin(PIN_LED_PGM, $3); } |
  K_VFYLED TKN_EQUAL TKN_NUMBER { assign_pin(PIN_LED_VFY, $3); }
;


part_parms :
  part_parm TKN_SEMI |
  part_parms part_parm TKN_SEMI
;


part_parm :
  K_ID TKN_EQUAL TKN_STRING 
    {
      strncpy(current_part->id, $3->value.string, AVR_IDLEN);
      current_part->id[AVR_IDLEN-1] = 0;
      free_token($3);
    } |

  K_DESC TKN_EQUAL TKN_STRING 
    {
      strncpy(current_part->desc, $3->value.string, AVR_DESCLEN);
      current_part->desc[AVR_DESCLEN-1] = 0;
      free_token($3);
    } |

  K_CHIP_ERASE_DELAY TKN_EQUAL TKN_NUMBER
    {
      current_part->chip_erase_delay = $3->value.number;
      free_token($3);
    } |

  K_EEPROM { current_mem = AVR_M_EEPROM; }
    mem_specs |

  K_FLASH { current_mem = AVR_M_FLASH; }
    mem_specs
;


yesno :
  K_YES | K_NO
;


mem_specs :
  mem_spec TKN_SEMI |
  mem_specs mem_spec TKN_SEMI
;


mem_spec :
  K_BANKED          TKN_EQUAL yesno
    {
      current_part->mem[current_mem].banked = $3->primary == K_YES ? 1 : 0;
      free_token($3);
    } |

  K_SIZE            TKN_EQUAL TKN_NUMBER
    {
      current_part->mem[current_mem].size = $3->value.number;
      free_token($3);
    } |


  K_BANK_SIZE       TKN_EQUAL TKN_NUMBER
    {
      current_part->mem[current_mem].bank_size = $3->value.number;
      free_token($3);
    } |

  K_NUM_BANKS       TKN_EQUAL TKN_NUMBER
    {
      current_part->mem[current_mem].num_banks = $3->value.number;
      free_token($3);
    } |

  K_MIN_WRITE_DELAY TKN_EQUAL TKN_NUMBER
    {
      current_part->mem[current_mem].min_write_delay = $3->value.number;
      free_token($3);
    } |

  K_MAX_WRITE_DELAY TKN_EQUAL TKN_NUMBER
    {
      current_part->mem[current_mem].max_write_delay = $3->value.number;
      free_token($3);
    } |

  K_READBACK_P1     TKN_EQUAL TKN_NUMBER
    {
      current_part->mem[current_mem].readback[0] = $3->value.number;
      free_token($3);
    } |

  K_READBACK_P2     TKN_EQUAL TKN_NUMBER
    {
      current_part->mem[current_mem].readback[1] = $3->value.number;
      free_token($3);
    }
;


%%

#include <string.h>
#include <math.h>

#include "config.h"
#include "lists.h"
#include "pindefs.h"
#include "avr.h"

extern char * progname;

int yylex(void);
int yyerror(char * errmsg);


#if 0
static char * vtypestr(int type)
{
  switch (type) {
    case V_NUM : return "NUMERIC";
    case V_STR : return "STRING";
    default:
      return "<UNKNOWN>";
  }
}
#endif


static int assign_pin(int pinno, TOKEN * v)
{
  int value;

  value = v->value.number;

  if ((value <= 0) || (value >= 18)) {
    fprintf(stderr, 
            "%s: error at line %d of %s: pin must be in the "
            "range 1-17\n",
            progname, lineno, infile);
    exit(1);
  }

  current_prog->pinno[pinno] = value;

  return 0;
}

