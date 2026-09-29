import ctypes, ctypes.wintypes as w, sys, os, struct, time
k32 = ctypes.windll.kernel32
DEBUG_ONLY_THIS_PROCESS = 0x2; DBG_CONTINUE = 0x00010002
class SI(ctypes.Structure):
    _fields_=[('cb',w.DWORD),('r',w.LPWSTR),('d',w.LPWSTR),('t',w.LPWSTR),('x',w.DWORD),('y',w.DWORD),
              ('xs',w.DWORD),('ys',w.DWORD),('xc',w.DWORD),('yc',w.DWORD),('fa',w.DWORD),('fl',w.DWORD),
              ('sw',w.WORD),('cr',w.WORD),('pr',ctypes.c_void_p),('hi',w.HANDLE),('ho',w.HANDLE),('he',w.HANDLE)]
class PI(ctypes.Structure):
    _fields_=[('hp',w.HANDLE),('ht',w.HANDLE),('pid',w.DWORD),('tid',w.DWORD)]
exe, wd = sys.argv[1], sys.argv[2]
si=SI(); si.cb=ctypes.sizeof(si); pi=PI()
ok=k32.CreateProcessW(exe, ctypes.c_wchar_p('"'+exe+'"'), None,None,False,DEBUG_ONLY_THIS_PROCESS,None,wd,ctypes.byref(si),ctypes.byref(pi))
if not ok: print('fail', ctypes.GetLastError()); sys.exit(1)
buf=ctypes.create_string_buffer(200)
n=0; t0=time.time(); excs=0
while time.time()-t0 < 40:
    if not k32.WaitForDebugEvent(buf, 2000): continue
    code,pid,tid = struct.unpack_from('<III', buf.raw, 0)
    raw = buf.raw
    if code == 6:
        base, = struct.unpack_from('<Q', raw, 16)
        print('LOADDLL base=%#x' % base)
    elif code == 1:
        ec, = struct.unpack_from('<I', raw, 16)
        ea, = struct.unpack_from('<Q', raw, 32)
        fc, = struct.unpack_from('<I', raw, 16+152)
        if ec in (0x80000003,): 
            pass
        else:
            # resolve module + RVA
            import ctypes.wintypes as wt
            class ME(ctypes.Structure):
                _fields_=[('dwSize',w.DWORD),('th32ModuleID',w.DWORD),('th32ProcessID',w.DWORD),
                          ('GlblcntUsage',w.DWORD),('ProccntUsage',w.DWORD),('modBaseAddr',ctypes.c_void_p),
                          ('modBaseSize',w.DWORD),('hModule',w.HMODULE),('szModule',w.WCHAR*256),('szExePath',w.WCHAR*260)]
            snap=k32.CreateToolhelp32Snapshot(0x8|0x10, pid)
            me=ME(); me.dwSize=ctypes.sizeof(ME); info=''
            if k32.Module32FirstW(snap, ctypes.byref(me)):
                while True:
                    b=me.modBaseAddr or 0
                    if b <= ea < b+me.modBaseSize:
                        info='%s+%#x' % (me.szModule, ea-b); break
                    if not k32.Module32NextW(snap, ctypes.byref(me)): break
            k32.CloseHandle(snap)
            print('EXC code=%#x mod=%s first=%d tid=%d' % (ec, info, fc, tid)); excs+=1
            if excs > 4: break
    elif code == 5:
        print('EXITED'); break
    k32.ContinueDebugEvent(pid, tid, DBG_CONTINUE)
k32.TerminateProcess(pi.hp, 0)
