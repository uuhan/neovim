if exists('g:loaded_node_provider')
  finish
endif
let g:loaded_node_provider = 1

let s:job_opts = {'rpc': v:true, 'on_stderr': function('provider#stderr_collector')}

function! s:is_minimum_version(version, min_major, min_minor) abort
  let nodejs_version = a:version
  if !a:version
    let nodejs_version = get(split(system(['node', '-v']), "\n"), 0, '')
    if v:shell_error || nodejs_version[0] !=# 'v'
      return 0
    endif
  endif
  " [major, minor, patch]
  let v_list = !!a:version ? a:version : split(nodejs_version[1:], '\.')
  return len(v_list) == 3
    \ && ((str2nr(v_list[0]) > str2nr(a:min_major))
    \     || (str2nr(v_list[0]) == str2nr(a:min_major)
    \         && str2nr(v_list[1]) >= str2nr(a:min_minor)))
endfunction

" Support for --inspect-brk requires node 6.12+ or 7.6+ or 8+
" Return 1 if it is supported
" Return 0 otherwise
function! provider#node#can_inspect() abort
  if !executable('node')
    return 0
  endif
  let ver = get(split(system(['node', '-v']), "\n"), 0, '')
  if v:shell_error || ver[0] !=# 'v'
    return 0
  endif
  return (ver[1] ==# '6' && s:is_minimum_version(ver, 6, 12))
    \ || s:is_minimum_version(ver, 7, 6)
endfunction

function! provider#node#Detect() abort
  let global_modules = get(split(system('npm root -g'), "\n"), 0, '')
  if v:shell_error || !isdirectory(global_modules)
    return ''
  endif
  if !s:is_minimum_version(v:null, 6, 0)
    return ''
  endif
  let entry_point = glob(global_modules . '/neovim/bin/cli.js')
  if !filereadable(entry_point)
    return ''
  endif
  return entry_point
endfunction

function! provider#node#Prog() abort
  return s:prog
endfunction

function! provider#node#Require(host) abort
  if s:err != ''
    echoerr s:err
    return
  endif

  let args = ['node']

  if !empty($NVIM_NODE_HOST_DEBUG) && provider#node#can_inspect()
    call add(args, '--inspect-brk')
  endif

  call add(args, provider#node#Prog())

  try
    let channel_id = jobstart(args, s:job_opts)
    if rpcrequest(channel_id, 'poll') ==# 'ok'
      return channel_id
    endif
  catch
    echomsg v:throwpoint
    echomsg v:exception
    for row in provider#get_stderr(channel_id)
      echomsg row
    endfor
  endtry
  finally
    call provider#clear_stderr(channel_id)
  endtry
  throw remote#host#LoadErrorForHost(a:host.orig_name, '$NVIM_NODE_LOG_FILE')
endfunction

function! provider#node#Call(method, args) abort
  if s:err != ''
    echoerr s:err
    return
  endif

  if !exists('s:host')
    try
      let s:host = remote#host#Require('node')
    catch
      let s:err = v:exception
      echohl WarningMsg
      echomsg v:exception
      echohl None
      return
    endtry
  endif
  return call('rpcrequest', insert(insert(a:args, 'node_'.a:method), s:host))
endfunction


let s:err = ''
let s:prog = provider#node#Detect()

if empty(s:prog)
  let s:err = 'Cannot find the "neovim" node package. Try :CheckHealth'
endif

call remote#host#RegisterPlugin('node-provider', 'node', [])
