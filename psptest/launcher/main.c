#include <kubridge.h>
#include <pspctrl.h>
#include <pspdebug.h>
#include <pspiofilemgr.h>
#include <pspkernel.h>
#include <pspmodulemgr.h>
#include <pspthreadman.h>
#include <psptest.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

PSP_MODULE_INFO("PSPDEV PSPTEST Launcher", 0, 1, 0);
PSP_MAIN_THREAD_ATTR(PSP_THREAD_ATTR_USER);
PSP_HEAP_SIZE_KB(1024);

#define COLOR_WHITE 0xFFFFFFFFu
#define COLOR_AMBER 0xFF00BFFFu
#define COLOR_GRAY  0xFFD3D3D3u
#define COLOR_RED   0xFF0000FFu
#define COLOR_GREEN 0xFF00FF00u

#define MAX_TESTS 128
#define PAGE_ROWS 20

typedef enum TestStatus {
    TEST_PENDING = 0,
    TEST_PASS,
    TEST_FAIL,
    TEST_WARNING
} TestStatus;

typedef struct TestEntry {
    char module[64];
    char relative_path[128];
    char kind[16];
    TestStatus status;
    unsigned int passed;
    unsigned int failed;
    unsigned int skipped;
    unsigned int total;
} TestEntry;

typedef struct RunState {
    int running;
    int index;
    char module[64];
    char mode[16];
} RunState;

static TestEntry tests[MAX_TESTS];
static int test_count;
static char root_path[256];
static char interrupted_module[64];
static char last_launch_stage[32];
static int last_launch_error;

static void set_color(unsigned int color) {
    pspDebugScreenSetTextColor(color);
}

static void print_header(const char *title) {
    pspDebugScreenClear();
    set_color(COLOR_AMBER);
    pspDebugScreenPrintf("PSPTEST  %s\n", title);
    pspDebugScreenPrintf("------------------------------------------------------------\n");
    set_color(COLOR_WHITE);
}

static void print_note(const char *text) {
    set_color(COLOR_GRAY);
    pspDebugScreenPrintf("%s\n", text);
    set_color(COLOR_WHITE);
}

static const char *status_name(TestStatus status) {
    switch (status) {
        case TEST_PASS: return "PASS";
        case TEST_FAIL: return "FAIL";
        case TEST_WARNING: return "WARN";
        default: return "PENDING";
    }
}

static unsigned int status_color(TestStatus status) {
    switch (status) {
        case TEST_PASS: return COLOR_GREEN;
        case TEST_FAIL: return COLOR_RED;
        case TEST_WARNING: return COLOR_AMBER;
        default: return COLOR_WHITE;
    }
}

static int make_path(char *destination, size_t destination_size, const char *suffix) {
    size_t root_length = strlen(root_path);
    size_t suffix_length = strlen(suffix);

    if (root_length + 1 + suffix_length + 1 > destination_size) {
        if (destination_size > 0) {
            destination[0] = '\0';
        }
        return -1;
    }

    memcpy(destination, root_path, root_length);
    destination[root_length] = '/';
    memcpy(destination + root_length + 1, suffix, suffix_length + 1);
    return 0;
}

static void derive_root_path(int argc, char **argv) {
    const char *fallback = "ms0:/PSP/GAME/psptest";
    size_t length;

    if (argc <= 0 || argv == NULL || argv[0] == NULL || argv[0][0] == '\0') {
        snprintf(root_path, sizeof(root_path), "%s", fallback);
    } else {
        snprintf(root_path, sizeof(root_path), "%s", argv[0]);
        length = strlen(root_path);
        while (length > 0 && root_path[length - 1] != '/' && root_path[length - 1] != ':') {
            root_path[--length] = '\0';
        }
        if (length > 0 && root_path[length - 1] == '/') {
            root_path[length - 1] = '\0';
        }
        if (root_path[0] == '\0') {
            snprintf(root_path, sizeof(root_path), "%s", fallback);
        }
    }
}

static unsigned int read_press(void) {
    SceCtrlData pad;

    do {
        sceCtrlReadBufferPositive(&pad, 1);
        sceKernelDelayThread(10000);
    } while (pad.Buttons != 0);

    do {
        sceCtrlReadBufferPositive(&pad, 1);
        sceKernelDelayThread(10000);
    } while (pad.Buttons == 0);

    return pad.Buttons;
}

static int load_manifest(void) {
    char path[320];
    char line[320];
    FILE *file;

    if (make_path(path, sizeof(path), "manifest.tsv") != 0) {
        return -1;
    }
    file = fopen(path, "r");
    if (file == NULL) {
        return -1;
    }

    test_count = 0;
    while (fgets(line, sizeof(line), file) != NULL && test_count < MAX_TESTS) {
        TestEntry *entry;

        if (strncmp(line, "TEST\t", 5) != 0) {
            continue;
        }

        entry = &tests[test_count];
        memset(entry, 0, sizeof(*entry));
        if (sscanf(line, "TEST\t%63[^\t]\t%127[^\t]\t%15[^\r\n]", entry->module, entry->relative_path, entry->kind) == 3) {
            test_count++;
        }
    }

    fclose(file);
    return test_count;
}

static int load_result(TestEntry *entry) {
    char suffix[160];
    char path[320];
    char line[320];
    FILE *file;

    snprintf(suffix, sizeof(suffix), "results/%s.log", entry->module);
    if (make_path(path, sizeof(path), suffix) != 0) {
        entry->status = TEST_WARNING;
        return -1;
    }
    file = fopen(path, "r");
    if (file == NULL) {
        entry->status = TEST_PENDING;
        return 0;
    }

    entry->status = TEST_WARNING;
    while (fgets(line, sizeof(line), file) != NULL) {
        unsigned int pass;
        unsigned int fail;
        unsigned int skip;
        unsigned int total;

        if (sscanf(line, "SUMMARY\tpass=%u\tfail=%u\tskip=%u\ttotal=%u", &pass, &fail, &skip, &total) == 4) {
            entry->passed = pass;
            entry->failed = fail;
            entry->skipped = skip;
            entry->total = total;
            if (fail != 0) {
                entry->status = TEST_FAIL;
            } else if (skip != 0) {
                entry->status = TEST_WARNING;
            } else {
                entry->status = TEST_PASS;
            }
            fclose(file);
            return 1;
        }
    }

    fclose(file);
    return -1;
}

static void load_results(void) {
    int index;

    for (index = 0; index < test_count; index++) {
        load_result(&tests[index]);
        if (interrupted_module[0] != '\0' && strcmp(tests[index].module, interrupted_module) == 0 && tests[index].status == TEST_PENDING) {
            tests[index].status = TEST_WARNING;
        }
    }
}

static int write_state(const char *mode, int index) {
    char temp_path[320];
    char state_path[320];
    FILE *file;

    if (make_path(temp_path, sizeof(temp_path), "state.tmp") != 0 ||
        make_path(state_path, sizeof(state_path), "state.tsv") != 0) {
        return -1;
    }

    file = fopen(temp_path, "w");
    if (file == NULL) {
        return -1;
    }

    if (index >= 0 && index < test_count) {
        fprintf(file, "RUNNING\t%s\t%s\t%d\n", tests[index].module, mode, index);
    } else {
        fprintf(file, "IDLE\n");
    }

    if (fflush(file) != 0 || fclose(file) != 0) {
        remove(temp_path);
        return -1;
    }

    remove(state_path);
    if (rename(temp_path, state_path) != 0) {
        remove(temp_path);
        return -1;
    }

    return 0;
}

static RunState read_state(void) {
    char path[320];
    char line[256];
    FILE *file;
    RunState state;

    memset(&state, 0, sizeof(state));
    state.index = -1;

    if (make_path(path, sizeof(path), "state.tsv") != 0) {
        return state;
    }
    file = fopen(path, "r");
    if (file == NULL) {
        return state;
    }

    if (fgets(line, sizeof(line), file) != NULL &&
        sscanf(line, "RUNNING\t%63[^\t]\t%15[^\t]\t%d", state.module, state.mode, &state.index) == 3) {
        state.running = 1;
    }

    fclose(file);
    return state;
}

static int result_path_for(int index, char *path, size_t path_size) {
    char suffix[160];
    int length = snprintf(suffix, sizeof(suffix), "results/%s.log", tests[index].module);

    if (length < 0 || (size_t)length >= sizeof(suffix)) {
        if (path_size > 0) {
            path[0] = '\0';
        }
        return -1;
    }

    return make_path(path, path_size, suffix);
}

typedef struct SupervisorRequest {
    int index;
    int result;
    const char *failure_stage;
} SupervisorRequest;

static SupervisorRequest supervisor_request;

static int supervisor_thread(SceSize args, void *argp) {
    SupervisorRequest *request = &supervisor_request;

    (void)args;
    (void)argp;
    PspTestModuleControl control;
    char module_args[512];
    char child_path[384];
    char result_path[320];
    SceUID module_id = -1;
    SceUID completion_sema = -1;
    int module_status = 0;
    int result = -1;

    if (request->index < 0 || request->index >= test_count) {
        request->failure_stage = "request";
        request->result = -1;
        return 0;
    }

    if (make_path(child_path, sizeof(child_path), tests[request->index].relative_path) != 0 ||
        result_path_for(request->index, result_path, sizeof(result_path)) != 0) {
        request->failure_stage = "path";
        request->result = -2;
        return 0;
    }

    remove(result_path);
    completion_sema = sceKernelCreateSema("psptest-complete", 0, 0, 1, NULL);
    if (completion_sema < 0) {
        request->failure_stage = "semaphore";
        request->result = completion_sema;
        return 0;
    }

    memset(&control, 0, sizeof(control));
    control.size = sizeof(control);
    control.version = PSPTEST_MODULE_ABI_VERSION;
    control.completion_sema = completion_sema;
    control.test_thread = -1;
    control.state = PSPTEST_MODULE_IDLE;
    control.result = 2;
    snprintf(control.output_path, sizeof(control.output_path), "%s", result_path);

    {
        int first_length = snprintf(module_args, sizeof(module_args), "%s", child_path);
        int second_length;
        if (first_length < 0 || (size_t)first_length + 1 >= sizeof(module_args)) {
            request->failure_stage = "arguments";
            result = -2;
            goto done;
        }
        second_length = snprintf(module_args + first_length + 1, sizeof(module_args) - (size_t)first_length - 1, "--psptest-control=0x%08X", (unsigned int)(uintptr_t)&control);
        if (second_length < 0 || (size_t)first_length + (size_t)second_length + 2 > sizeof(module_args)) {
            request->failure_stage = "arguments";
            result = -2;
            goto done;
        }
    }

    module_id = kuKernelLoadModule(child_path, 0, NULL);
    if (module_id < 0) {
        request->failure_stage = "load";
        result = module_id;
        goto done;
    }

    {
        size_t first_length = strlen(module_args);
        size_t second_length = strlen(module_args + first_length + 1);
        SceSize module_args_size = (SceSize)(first_length + second_length + 2);
        result = sceKernelStartModule(module_id, module_args_size, module_args, &module_status, NULL);
    }
    if (result < 0) {
        request->failure_stage = "start";
        goto done;
    }

    result = sceKernelWaitSema(completion_sema, 1, NULL);
    if (result < 0) {
        request->failure_stage = "wait";
        goto done;
    }

    result = control.state == PSPTEST_MODULE_COMPLETE ? control.result : (control.result < 0 ? control.result : -1);
    if (control.state != PSPTEST_MODULE_COMPLETE) {
        request->failure_stage = "test";
    }
    if (control.test_thread > 0) {
        sceKernelWaitThreadEnd(control.test_thread, NULL);
    }

done:
    if (module_id >= 0) {
        sceKernelStopModule(module_id, 0, NULL, &module_status, NULL);
        sceKernelUnloadModule(module_id);
    }
    if (completion_sema >= 0) {
        sceKernelDeleteSema(completion_sema);
    }

    request->result = result;
    return 0;
}

static int launch_test(int index, const char *mode) {
    SupervisorRequest *request = &supervisor_request;
    SceUID supervisor;
    int result;

    if (index < 0 || index >= test_count) {
        return -1;
    }

    if (write_state(mode, index) != 0) {
        return -2;
    }

    print_header("Running");
    pspDebugScreenPrintf("%s\n\n", tests[index].module);
    print_note("The test module is running on a dedicated test thread.");

    last_launch_stage[0] = '\0';
    last_launch_error = 0;
    request->index = index;
    request->result = -1;
    request->failure_stage = NULL;

    supervisor = sceKernelCreateThread("psptest-supervisor", supervisor_thread, 0x18, 0x10000, PSP_THREAD_ATTR_USER, NULL);
    if (supervisor < 0) {
        snprintf(last_launch_stage, sizeof(last_launch_stage), "%s", "supervisor-create");
        last_launch_error = supervisor;
        write_state("idle", -1);
        return supervisor;
    }

    result = sceKernelStartThread(supervisor, 0, NULL);
    if (result < 0) {
        snprintf(last_launch_stage, sizeof(last_launch_stage), "%s", "supervisor-start");
        last_launch_error = result;
    } else {
        result = sceKernelWaitThreadEnd(supervisor, NULL);
        if (result < 0 && request->failure_stage == NULL && request->result == -1) {
            snprintf(last_launch_stage, sizeof(last_launch_stage), "%s", "supervisor");
            last_launch_error = result;
        }
    }
    sceKernelDeleteThread(supervisor);
    write_state("idle", -1);

    if (request->failure_stage == NULL && request->result == -1 && result < 0) {
        return result;
    }
    if (request->result < 0) {
        snprintf(last_launch_stage, sizeof(last_launch_stage), "%s", request->failure_stage != NULL ? request->failure_stage : "module");
        last_launch_error = request->result;
    }
    return request->result;
}

static void count_statuses(int *passed, int *failed, int *warnings, int *pending) {
    int index;

    *passed = 0;
    *failed = 0;
    *warnings = 0;
    *pending = 0;

    for (index = 0; index < test_count; index++) {
        switch (tests[index].status) {
            case TEST_PASS: (*passed)++; break;
            case TEST_FAIL: (*failed)++; break;
            case TEST_WARNING: (*warnings)++; break;
            default: (*pending)++; break;
        }
    }
}

static void show_summary(void) {
    int passed;
    int failed;
    int warnings;
    int pending;

    count_statuses(&passed, &failed, &warnings, &pending);
    print_header("Results");

    set_color(COLOR_WHITE);
    pspDebugScreenPrintf("Tests:    %d\n\n", test_count);

    set_color(COLOR_GREEN);
    pspDebugScreenPrintf("PASS      %d\n", passed);
    set_color(COLOR_RED);
    pspDebugScreenPrintf("FAIL      %d\n", failed);
    set_color(COLOR_AMBER);
    pspDebugScreenPrintf("WARN      %d\n", warnings);
    set_color(COLOR_WHITE);
    pspDebugScreenPrintf("PENDING   %d\n\n", pending);

    if (interrupted_module[0] != '\0') {
        set_color(COLOR_AMBER);
        pspDebugScreenPrintf("Interrupted: %s\n\n", interrupted_module);
    }

    print_note("WARN includes skipped, incomplete, or interrupted tests.");
    print_note("Press O to return.");
    while ((read_press() & PSP_CTRL_CIRCLE) == 0) {
    }
}

static void browse_tests(void) {
    int selected = 0;

    if (test_count == 0) {
        return;
    }

    for (;;) {
        int first = (selected / PAGE_ROWS) * PAGE_ROWS;
        int last = first + PAGE_ROWS;
        int index;
        unsigned int buttons;

        if (last > test_count) {
            last = test_count;
        }

        print_header("Browse");
        for (index = first; index < last; index++) {
            set_color(index == selected ? COLOR_AMBER : COLOR_WHITE);
            pspDebugScreenPrintf("%c %-30s ", index == selected ? '>' : ' ', tests[index].module);
            set_color(status_color(tests[index].status));
            pspDebugScreenPrintf("%s\n", status_name(tests[index].status));
        }

        pspDebugScreenPrintf("\n");
        print_note("UP/DOWN select   X run   O back");

        buttons = read_press();
        if ((buttons & PSP_CTRL_UP) != 0) {
            selected = selected == 0 ? test_count - 1 : selected - 1;
        } else if ((buttons & PSP_CTRL_DOWN) != 0) {
            selected = selected + 1 == test_count ? 0 : selected + 1;
        } else if ((buttons & PSP_CTRL_CROSS) != 0) {
            int result = launch_test(selected, "single");
            if (result < 0) {
                tests[selected].status = TEST_WARNING;
                print_header("Warning");
                set_color(COLOR_AMBER);
                pspDebugScreenPrintf("Could not launch %s\n", tests[selected].module);
                pspDebugScreenPrintf("Stage: %s\n", last_launch_stage[0] != '\0' ? last_launch_stage : "unknown");
                pspDebugScreenPrintf("Error: 0x%08X (%d)\n", (unsigned int)last_launch_error, last_launch_error);
                print_note("Press O to return.");
                while ((read_press() & PSP_CTRL_CIRCLE) == 0) {
                }
            }
            return;
        } else if ((buttons & PSP_CTRL_CIRCLE) != 0) {
            return;
        }
    }
}

int main(int argc, char **argv) {
    RunState state;

    pspDebugScreenInit();
    sceCtrlSetSamplingCycle(0);
    sceCtrlSetSamplingMode(PSP_CTRL_MODE_DIGITAL);

    derive_root_path(argc, argv);

    if (load_manifest() < 0) {
        print_header("Error");
        set_color(COLOR_RED);
        pspDebugScreenPrintf("manifest.tsv could not be opened.\n\n");
        print_note(root_path);
        print_note("Press START to exit.");
        while ((read_press() & PSP_CTRL_START) == 0) {
        }
        sceKernelExitGame();
        return 1;
    }

    {
        char results_path[320];
        if (make_path(results_path, sizeof(results_path), "results") == 0) {
            sceIoMkdir(results_path, 0777);
        }
    }

    load_results();
    state = read_state();
    if (state.running) {
        snprintf(interrupted_module, sizeof(interrupted_module), "%s", state.module);
        if (state.index >= 0 && state.index < test_count) {
            tests[state.index].status = TEST_WARNING;
        }
        write_state("idle", -1);
    }

    for (;;) {
        int passed;
        int failed;
        int warnings;
        int pending;
        unsigned int buttons;

        load_results();
        count_statuses(&passed, &failed, &warnings, &pending);

        print_header("Hardware Test Launcher");

        set_color(COLOR_WHITE);
        pspDebugScreenPrintf("Tests: %d   ", test_count);
        set_color(COLOR_GREEN);
        pspDebugScreenPrintf("PASS %d   ", passed);
        set_color(COLOR_RED);
        pspDebugScreenPrintf("FAIL %d   ", failed);
        set_color(COLOR_AMBER);
        pspDebugScreenPrintf("WARN %d   ", warnings);
        set_color(COLOR_WHITE);
        pspDebugScreenPrintf("PENDING %d\n\n", pending);

        if (interrupted_module[0] != '\0') {
            set_color(COLOR_AMBER);
            pspDebugScreenPrintf("Previous test interrupted: %s\n\n", interrupted_module);
        }

        set_color(COLOR_WHITE);
        pspDebugScreenPrintf("X       Run all automated tests\n");
        pspDebugScreenPrintf("O       Browse tests\n");
        pspDebugScreenPrintf("[]      Rerun failures\n");
        pspDebugScreenPrintf("TRIANGLE Results\n");
        pspDebugScreenPrintf("START   Exit\n\n");
        print_note("Each test runs as a user PRX under the persistent launcher.");

        buttons = read_press();
        if ((buttons & PSP_CTRL_CROSS) != 0) {
            int index;
            for (index = 0; index < test_count; index++) {
                int run_result = launch_test(index, "all");
                load_result(&tests[index]);
                if (run_result < 0) {
                    tests[index].status = TEST_WARNING;
                    break;
                }
            }
        } else if ((buttons & PSP_CTRL_CIRCLE) != 0) {
            browse_tests();
        } else if ((buttons & PSP_CTRL_SQUARE) != 0) {
            int index;
            for (index = 0; index < test_count; index++) {
                if (tests[index].status == TEST_FAIL) {
                    int run_result = launch_test(index, "failed");
                    load_result(&tests[index]);
                    if (run_result < 0) {
                        tests[index].status = TEST_WARNING;
                        break;
                    }
                }
            }
        } else if ((buttons & PSP_CTRL_TRIANGLE) != 0) {
            show_summary();
        } else if ((buttons & PSP_CTRL_START) != 0) {
            sceKernelExitGame();
            return 0;
        }
    }
}
