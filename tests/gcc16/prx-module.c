#include <pspkernel.h>
#include <pspdisplay.h>

PSP_MODULE_INFO("gcc16-prx", PSP_MODULE_USER, 1, 0);

int module_start(SceSize args, void *argp)
{
    (void)args;
    (void)argp;
    /* Exercise a real SDK import so PRX generation produces .lib.stub. */
    (void)sceDisplayGetVcount();
    return 0;
}

int module_stop(SceSize args, void *argp)
{
    (void)args;
    (void)argp;
    return 0;
}
