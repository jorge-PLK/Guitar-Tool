#include "CChildProcess.h"
typedef int CChildProcess_empty_translation_unit;

// Contrato en include/CChildProcess.h (plan, «Fase 7c», paso 8).
#if defined(_WIN32)
#if !defined(_WIN32_WINNT) || _WIN32_WINNT < 0x0A00
#undef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00
#endif
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

void *tf_child_parent_std(int32_t which) {
    DWORD id = which == 0 ? STD_INPUT_HANDLE : (which == 1 ? STD_OUTPUT_HANDLE : STD_ERROR_HANDLE);
    HANDLE h = GetStdHandle(id);
    return h == INVALID_HANDLE_VALUE ? NULL : h;
}

/// Copia heredable de `h` (NULL si no hay o no se puede duplicar).
static HANDLE dup_inheritable(HANDLE h) {
    HANDLE copy = NULL;
    if (h == NULL || h == INVALID_HANDLE_VALUE) return NULL;
    if (!DuplicateHandle(GetCurrentProcess(), h, GetCurrentProcess(), &copy, 0, TRUE, DUPLICATE_SAME_ACCESS))
        return NULL;
    return copy;
}

uint32_t tf_child_spawn(const uint16_t *command_line, const uint16_t *environment, const uint16_t *directory,
                        void *std_in, void *std_out, void *std_err, void *job, tf_child_info *out) {
    memset(out, 0, sizeof *out);
    if (command_line == NULL) return ERROR_INVALID_PARAMETER;

    // CreateProcessW puede escribir en la línea de órdenes: va en una copia propia.
    size_t len = wcslen((const wchar_t *)command_line);
    wchar_t *cmd = (wchar_t *)malloc((len + 1) * sizeof(wchar_t));
    if (cmd == NULL) return ERROR_NOT_ENOUGH_MEMORY;
    memcpy(cmd, command_line, (len + 1) * sizeof(wchar_t));

    // Los tres handles del hijo, heredables y propios (se cierran tras crear el proceso). Lo que falte, a NUL.
    HANDLE given[3] = { (HANDLE)std_in, (HANDLE)std_out, (HANDLE)std_err };
    HANDLE child[3] = { NULL, NULL, NULL };
    HANDLE nul = NULL;
    for (int i = 0; i < 3; i++) {
        child[i] = dup_inheritable(given[i]);
        if (child[i] == NULL) {
            if (nul == NULL) {
                SECURITY_ATTRIBUTES sa;
                sa.nLength = sizeof sa;
                sa.lpSecurityDescriptor = NULL;
                sa.bInheritHandle = TRUE;
                nul = CreateFileW(L"NUL", GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, &sa,
                                  OPEN_EXISTING, 0, NULL);
                if (nul == INVALID_HANDLE_VALUE) nul = NULL;
            }
            child[i] = nul;
        }
    }

    // Lista de heredables sin repetidos ni NULL (UpdateProcThreadAttribute rechaza repetidos).
    HANDLE list[3];
    DWORD count = 0;
    for (int i = 0; i < 3; i++) {
        if (child[i] == NULL) continue;
        int seen = 0;
        for (DWORD j = 0; j < count; j++) if (list[j] == child[i]) seen = 1;
        if (!seen) list[count++] = child[i];
    }

    STARTUPINFOEXW si;
    ZeroMemory(&si, sizeof si);
    si.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    si.StartupInfo.hStdInput = child[0];
    si.StartupInfo.hStdOutput = child[1];
    si.StartupInfo.hStdError = child[2];

    LPPROC_THREAD_ATTRIBUTE_LIST attrs = NULL;
    if (count > 0) {
        SIZE_T size = 0;
        InitializeProcThreadAttributeList(NULL, 1, 0, &size);   // falla con ERROR_INSUFFICIENT_BUFFER y da el tamaño
        if (size > 0) attrs = (LPPROC_THREAD_ATTRIBUTE_LIST)HeapAlloc(GetProcessHeap(), 0, size);
        if (attrs != NULL) {
            if (!InitializeProcThreadAttributeList(attrs, 1, 0, &size)) {
                HeapFree(GetProcessHeap(), 0, attrs);
                attrs = NULL;
            } else if (!UpdateProcThreadAttribute(attrs, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST, list,
                                                  count * sizeof(HANDLE), NULL, NULL)) {
                DeleteProcThreadAttributeList(attrs);
                HeapFree(GetProcessHeap(), 0, attrs);
                attrs = NULL;
            }
        }
    }

    DWORD flags = CREATE_NO_WINDOW | CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT;
    if (attrs != NULL) {
        si.StartupInfo.cb = sizeof(STARTUPINFOEXW);
        si.lpAttributeList = attrs;
        flags |= EXTENDED_STARTUPINFO_PRESENT;
    } else {
        // Sin lista: hereda todos los heredables (lo que hacía Foundation `Process`).
        si.StartupInfo.cb = sizeof(STARTUPINFOW);
    }

    PROCESS_INFORMATION pi;
    ZeroMemory(&pi, sizeof pi);
    BOOL ok = CreateProcessW(NULL, cmd, NULL, NULL, TRUE, flags, (LPVOID)environment, (LPCWSTR)directory,
                             &si.StartupInfo, &pi);
    DWORD error = ok ? 0 : GetLastError();

    if (attrs != NULL) {
        DeleteProcThreadAttributeList(attrs);
        HeapFree(GetProcessHeap(), 0, attrs);
    }
    free(cmd);
    for (int i = 0; i < 3; i++) if (child[i] != NULL && child[i] != nul) CloseHandle(child[i]);
    if (nul != NULL) CloseHandle(nul);

    if (!ok) return error != 0 ? error : ERROR_GEN_FAILURE;

    int32_t in_job = 0;
    if (job != NULL && AssignProcessToJobObject((HANDLE)job, pi.hProcess)) in_job = 1;
    if (ResumeThread(pi.hThread) == (DWORD)-1) {
        error = GetLastError();
        TerminateProcess(pi.hProcess, 1);
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
        return error != 0 ? error : ERROR_GEN_FAILURE;
    }
    CloseHandle(pi.hThread);
    out->process = pi.hProcess;
    out->pid = pi.dwProcessId;
    out->in_job = in_job;
    return 0;
}
#endif
