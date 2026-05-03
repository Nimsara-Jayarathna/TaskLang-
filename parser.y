%{
/*
 * TaskLang++ parser and semantic checker
 *
 * This file defines the grammar for TaskLang++ and stores parsed task
 * definitions in a fixed-size array. After parsing, semantic validation checks
 * duplicate task names, required RUN statements, references, schedules and
 * circular dependencies.
 */
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_TASKS 100
#define MAX_NAME_LEN 64
#define MAX_COMMAND_LEN 256
#define MAX_SCHEDULE_TYPE_LEN 32
#define MAX_FREQUENCY_LEN 16
#define MAX_TIME_LEN 16

typedef struct Task {
    char name[MAX_NAME_LEN];
    char command[MAX_COMMAND_LEN];
    char scheduleType[MAX_SCHEDULE_TYPE_LEN];
    char frequency[MAX_FREQUENCY_LEN];
    char time[MAX_TIME_LEN];
    char dependency[MAX_NAME_LEN];
    char beforeTask[MAX_NAME_LEN];
    char conditionTask[MAX_NAME_LEN];
    int hasRun;
    int hasSchedule;
    int hasDependency;
    int hasBefore;
    int hasCondition;
    int line;
} Task;

static Task tasks[MAX_TASKS];
static int taskCount = 0;
static int currentTask = -1;
static int semanticErrors = 0;
static int syntaxErrors = 0;

int yylex(void);
void yyerror(const char *message);

extern int yylineno;
extern char *yytext;

static void begin_task(const char *name);
static void finish_task(void);
static void set_run(const char *command);
static void set_schedule(const char *scheduleType, const char *frequency,
                         const char *time);
static void set_dependency(const char *dependency);
static void set_before(const char *beforeTask);
static void set_condition(const char *conditionTask);
static void copy_field(char *destination, size_t destinationSize,
                       const char *source, const char *fieldName);
static int validate_semantics(void);
static int validate_time(const char *time);
static int find_task(const char *name);
static int task_depends_on(int taskIndex, int prerequisiteIndex);
static int detect_cycles(void);
static int dfs_cycle(int index, int *state);
void print_execution(void);
static void print_execution_ordered(int index, int *printed);
static void print_execution_task(const Task *task);
%}

%error-verbose

%union {
    char *str;
}

%token TASK "TASK"
%token RUN "RUN"
%token EVERY "EVERY"
%token DAY "DAY"
%token WEEK "WEEK"
%token AT "AT"
%token AFTER "AFTER"
%token BEFORE "BEFORE"
%token DEPENDS "DEPENDS"
%token ON "ON"
%token IF "IF"
%token SUCCESS "success"
%token LBRACE "{"
%token RBRACE "}"
%token LPAREN "("
%token RPAREN ")"
%token <str> IDENTIFIER "identifier"
%token <str> STRING "string"
%token UNKNOWN "unknown token"

%destructor { free($$); } IDENTIFIER STRING

%%

program
    : task_list
    ;

task_list
    : task_definition
    | task_list task_definition
    ;

task_definition
    : TASK IDENTIFIER { begin_task($2); free($2); }
      LBRACE task_body RBRACE  { finish_task(); }
    ;

task_body
    : /* empty */
    | task_body task_statement
    ;

task_statement
    : RUN STRING
        {
            set_run($2);
            free($2);
        }
    | EVERY DAY AT STRING
        {
            set_schedule("EVERY", "DAY", $4);
            free($4);
        }
    | EVERY WEEK AT STRING
        {
            set_schedule("EVERY", "WEEK", $4);
            free($4);
        }
    | AT STRING
        {
            set_schedule("AT", "", $2);
            free($2);
        }
    | AFTER IDENTIFIER
        {
            set_dependency($2);
            free($2);
        }
    | BEFORE IDENTIFIER
        {
            set_before($2);
            free($2);
        }
    | DEPENDS ON IDENTIFIER
        {
            set_dependency($3);
            free($3);
        }
    | IF SUCCESS LPAREN IDENTIFIER RPAREN
        {
            set_condition($4);
            free($4);
        }
    ;

%%

int main(void)
{
    int parseResult = yyparse();

    if (parseResult != 0 || syntaxErrors > 0) {
        return EXIT_FAILURE;
    }

    validate_semantics();

    if (semanticErrors > 0) {
        printf("Semantic validation failed with %d error(s).\n",
               semanticErrors);
        return EXIT_FAILURE;
    }

    print_execution();
    return EXIT_SUCCESS;
}

void yyerror(const char *message)
{
    syntaxErrors++;

    if (yytext != NULL && yytext[0] != '\0') {
        fprintf(stderr, "Syntax error at line %d: %s near '%s'\n",
                yylineno, message, yytext);
    } else {
        fprintf(stderr, "Syntax error at line %d: %s\n", yylineno, message);
    }
}

static void begin_task(const char *name)
{
    Task *task;

    if (taskCount >= MAX_TASKS) {
        fprintf(stdout,
                "Semantic error at line %d: maximum number of tasks (%d) exceeded\n",
                yylineno, MAX_TASKS);
        semanticErrors++;
        currentTask = -1;
        return;
    }

    currentTask = taskCount;
    task = &tasks[taskCount];
    memset(task, 0, sizeof(*task));
    task->line = yylineno;
    copy_field(task->name, sizeof(task->name), name, "task name");
    taskCount++;
}

static void finish_task(void)
{
    currentTask = -1;
}

static void set_run(const char *command)
{
    Task *task;

    if (currentTask < 0) {
        return;
    }

    task = &tasks[currentTask];

    if (task->hasRun) {
        fprintf(stdout,
                "Semantic error at line %d: duplicate RUN statement in task '%s'\n",
                yylineno, task->name);
        semanticErrors++;
        return;
    }

    task->hasRun = 1;
    copy_field(task->command, sizeof(task->command), command, "command");
}

static void set_schedule(const char *scheduleType, const char *frequency,
                         const char *time)
{
    Task *task;

    if (currentTask < 0) {
        return;
    }

    task = &tasks[currentTask];

    if (task->hasSchedule) {
        fprintf(stdout,
                "Semantic error at line %d: duplicate schedule statement in task '%s'\n",
                yylineno, task->name);
        semanticErrors++;
        return;
    }

    task->hasSchedule = 1;
    copy_field(task->scheduleType, sizeof(task->scheduleType), scheduleType,
               "schedule type");
    copy_field(task->frequency, sizeof(task->frequency), frequency,
               "schedule frequency");
    copy_field(task->time, sizeof(task->time), time, "schedule time");
}

static void set_dependency(const char *dependency)
{
    Task *task;

    if (currentTask < 0) {
        return;
    }

    task = &tasks[currentTask];

    if (task->hasDependency) {
        fprintf(stdout,
                "Semantic error at line %d: duplicate dependency statement in task '%s'\n",
                yylineno, task->name);
        semanticErrors++;
        return;
    }

    if (task->hasBefore) {
        fprintf(stdout,
                "Semantic error at line %d: duplicate dependency statement in task '%s'\n",
                yylineno, task->name);
        semanticErrors++;
        return;
    }

    task->hasDependency = 1;
    copy_field(task->dependency, sizeof(task->dependency), dependency,
               "dependency");
}

static void set_before(const char *beforeTask)
{
    Task *task;

    if (currentTask < 0) {
        return;
    }

    task = &tasks[currentTask];

    if (task->hasDependency || task->hasBefore) {
        fprintf(stdout,
                "Semantic error at line %d: duplicate dependency statement in task '%s'\n",
                yylineno, task->name);
        semanticErrors++;
        return;
    }

    task->hasBefore = 1;
    copy_field(task->beforeTask, sizeof(task->beforeTask), beforeTask,
               "BEFORE task");
}

static void set_condition(const char *conditionTask)
{
    Task *task;

    if (currentTask < 0) {
        return;
    }

    task = &tasks[currentTask];

    if (task->hasCondition) {
        fprintf(stdout,
                "Semantic error at line %d: duplicate condition statement in task '%s'\n",
                yylineno, task->name);
        semanticErrors++;
        return;
    }

    task->hasCondition = 1;
    copy_field(task->conditionTask, sizeof(task->conditionTask), conditionTask,
               "condition task");
}

static void copy_field(char *destination, size_t destinationSize,
                       const char *source, const char *fieldName)
{
    if (strlen(source) >= destinationSize) {
        fprintf(stdout,
                "Semantic error at line %d: %s is too long and was truncated\n",
                yylineno, fieldName);
        semanticErrors++;
    }

    snprintf(destination, destinationSize, "%s", source);
}

static int validate_semantics(void)
{
    int before = semanticErrors;
    int i;
    int j;

    for (i = 0; i < taskCount; i++) {
        for (j = i + 1; j < taskCount; j++) {
            if (strcmp(tasks[i].name, tasks[j].name) == 0) {
                fprintf(stdout, "Semantic error: duplicate task name '%s'\n",
                        tasks[i].name);
                semanticErrors++;
            }
        }
    }

    for (i = 0; i < taskCount; i++) {
        if (!tasks[i].hasRun) {
            fprintf(stdout,
                    "Semantic error: task '%s' is missing required RUN statement\n",
                    tasks[i].name);
            semanticErrors++;
        }

        if (tasks[i].hasSchedule && !validate_time(tasks[i].time)) {
            fprintf(stdout,
                    "Semantic error: task '%s' has invalid time '%s' (expected HH:MM)\n",
                    tasks[i].name, tasks[i].time);
            semanticErrors++;
        }

        if (tasks[i].hasDependency && find_task(tasks[i].dependency) < 0) {
            fprintf(stdout,
                    "Semantic error: task '%s' depends on unknown task '%s'\n",
                    tasks[i].name, tasks[i].dependency);
            semanticErrors++;
        }

        if (tasks[i].hasBefore && find_task(tasks[i].beforeTask) < 0) {
            fprintf(stdout,
                    "Semantic error: task '%s' must run before unknown task '%s'\n",
                    tasks[i].name, tasks[i].beforeTask);
            semanticErrors++;
        }

        if (tasks[i].hasCondition && find_task(tasks[i].conditionTask) < 0) {
            fprintf(stdout,
                    "Semantic error: task '%s' has condition on unknown task '%s'\n",
                    tasks[i].name, tasks[i].conditionTask);
            semanticErrors++;
        }
    }

    detect_cycles();

    return semanticErrors - before;
}

static int validate_time(const char *time)
{
    int hour;
    int minute;

    if (strlen(time) != 5) {
        return 0;
    }

    if (!isdigit((unsigned char)time[0]) ||
        !isdigit((unsigned char)time[1]) ||
        time[2] != ':' ||
        !isdigit((unsigned char)time[3]) ||
        !isdigit((unsigned char)time[4])) {
        return 0;
    }

    hour = (time[0] - '0') * 10 + (time[1] - '0');
    minute = (time[3] - '0') * 10 + (time[4] - '0');

    return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;
}

static int find_task(const char *name)
{
    int i;

    for (i = 0; i < taskCount; i++) {
        if (strcmp(tasks[i].name, name) == 0) {
            return i;
        }
    }

    return -1;
}

/*
 * Dependency direction used by validation and execution ordering:
 * - AFTER/DEPENDS ON: the current task depends on the named task.
 * - BEFORE: the named task depends on the current task.
 */
static int task_depends_on(int taskIndex, int prerequisiteIndex)
{
    if (tasks[taskIndex].hasDependency &&
        strcmp(tasks[taskIndex].dependency, tasks[prerequisiteIndex].name) == 0) {
        return 1;
    }

    if (tasks[prerequisiteIndex].hasBefore &&
        strcmp(tasks[prerequisiteIndex].beforeTask, tasks[taskIndex].name) == 0) {
        return 1;
    }

    return 0;
}

static int detect_cycles(void)
{
    int state[MAX_TASKS];
    int i;

    for (i = 0; i < taskCount; i++) {
        state[i] = 0;
    }

    for (i = 0; i < taskCount; i++) {
        if (state[i] == 0 && dfs_cycle(i, state)) {
            return 1;
        }
    }

    return 0;
}

/*
 * DFS state values:
 * 0 = not visited, 1 = currently visiting, 2 = fully checked.
 */
static int dfs_cycle(int index, int *state)
{
    int dependencyIndex;

    state[index] = 1;

    for (dependencyIndex = 0; dependencyIndex < taskCount; dependencyIndex++) {
        if (!task_depends_on(index, dependencyIndex)) {
            continue;
        }

        if (state[dependencyIndex] == 1) {
            fprintf(stdout,
                    "Semantic error: circular dependency detected involving task '%s'\n",
                    tasks[dependencyIndex].name);
            semanticErrors++;
            return 1;
        }

        if (state[dependencyIndex] == 0 &&
            dfs_cycle(dependencyIndex, state)) {
            return 1;
        }
    }

    state[index] = 2;
    return 0;
}

/*
 * Print a simulated execution flow. This function does not execute scripts;
 * it only displays the order and metadata that would be used by a scheduler.
 */
void print_execution(void)
{
    int printed[MAX_TASKS];
    int i;

    for (i = 0; i < taskCount; i++) {
        printed[i] = 0;
    }

    printf("Parsing TaskLang++ input...\n\n");
    printf("--- EXECUTION START ---\n\n");

    for (i = 0; i < taskCount; i++) {
        print_execution_ordered(i, printed);
    }

    printf("--- EXECUTION COMPLETE ---\n");
}

/*
 * Bonus behavior: print dependency tasks first. Semantic validation has already
 * rejected unknown and circular dependencies before this function is called.
 */
static void print_execution_ordered(int index, int *printed)
{
    int dependencyIndex;

    if (printed[index]) {
        return;
    }

    for (dependencyIndex = 0; dependencyIndex < taskCount; dependencyIndex++) {
        if (task_depends_on(index, dependencyIndex)) {
            print_execution_ordered(dependencyIndex, printed);
        }
    }

    print_execution_task(&tasks[index]);
    printed[index] = 1;
}

static void print_execution_task(const Task *task)
{
    printf("Executing Task: %s\n", task->name);
    printf("  Script: \"%s\"\n", task->command);

    if (task->hasSchedule) {
        if (strcmp(task->scheduleType, "EVERY") == 0) {
            printf("  Schedule: EVERY %s AT %s\n",
                   task->frequency, task->time);
        } else {
            printf("  Schedule: AT %s\n", task->time);
        }
    } else {
        printf("  Schedule:\n");
    }

    if (task->hasDependency) {
        printf("  Depends on: %s\n", task->dependency);
    }

    if (task->hasBefore) {
        printf("  Before: %s\n", task->beforeTask);
    }

    if (task->hasCondition) {
        printf("  Condition: success\n");
    }

    printf("\n");
}
