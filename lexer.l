%{
/*
 * TaskLang++ lexer
 *
 * The lexer recognizes the keywords, identifiers, quoted strings and symbols
 * used by the TaskLang++ grammar. Whitespace and comments are ignored.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "parser.tab.h"

static char *copy_unquoted_string(const char *text);
%}

%option noyywrap
%option yylineno
%option nounput
%option noinput

%%

[ \t\r\n]+              ;
"//".*                  ;
"#".*                   ;

"TASK"                  { return TASK; }
"RUN"                   { return RUN; }
"EVERY"                 { return EVERY; }
"DAY"                   { return DAY; }
"WEEK"                  { return WEEK; }
"AT"                    { return AT; }
"AFTER"                 { return AFTER; }
"DEPENDS"               { return DEPENDS; }
"ON"                    { return ON; }
"IF"                    { return IF; }
"success"               { return SUCCESS; }

"{"                     { return LBRACE; }
"}"                     { return RBRACE; }
"("                     { return LPAREN; }
")"                     { return RPAREN; }

\"([^\\\"\n]|\\.)*\"   {
                            yylval.str = copy_unquoted_string(yytext);
                            return STRING;
                        }

\"([^\\\"\n]|\\.)*     {
                            yylval.str = strdup(yytext);
                            return UNKNOWN;
                        }

[A-Za-z_][A-Za-z0-9_]*  {
                            yylval.str = strdup(yytext);
                            return IDENTIFIER;
                        }

.                       {
                            yylval.str = strdup(yytext);
                            return UNKNOWN;
                        }

%%

/*
 * Remove the surrounding double quotes from a STRING token. A small amount of
 * escaping is supported so strings like "say \"hi\"" are stored as say "hi".
 */
static char *copy_unquoted_string(const char *text)
{
    size_t len = strlen(text);
    char *result = malloc(len);
    size_t out = 0;
    size_t i;

    if (result == NULL) {
        fprintf(stderr, "Fatal error: out of memory while reading string.\n");
        exit(EXIT_FAILURE);
    }

    for (i = 1; i + 1 < len; i++) {
        if (text[i] == '\\' && i + 1 < len - 1) {
            i++;
        }
        result[out++] = text[i];
    }

    result[out] = '\0';
    return result;
}
