" howm.vim - Minimal howm note-taking for vim
"
" Features:
"   goto links     (>>> keyword) - press <CR> to search notes for keyword
"   come-from links (<<< keyword) - press <CR> to search; matched files shown first
"   dated todos    ([YYYY-MM-DD]TYPE) - :HowmTodo lists today's relevant items
"
" Commands:
"   :HowmSearch {keyword}   search all notes for keyword
"   :HowmTodo               list todos relevant to today
"   :HowmNew                create a new timestamped note
"
" Configuration:
"   g:howm_dir    directory containing notes  (default: ~/howm/)
"   g:howm_glob   glob pattern for note files (default: **/*.txt)

if exists('g:loaded_howm')
  finish
endif
let g:loaded_howm = 1

let g:howm_dir  = get(g:, 'howm_dir',  expand('~/howm/'))
let g:howm_glob = get(g:, 'howm_glob', '**/*.txt')

if g:howm_dir[-1:] !=# '/'
  let g:howm_dir .= '/'
endif

" --------------------------------------------------------------------------
" Commands
" --------------------------------------------------------------------------

command! -nargs=1 HowmSearch call s:search(<q-args>)
command!          HowmTodo   call s:todo()
command!          HowmNew    call s:new_note()

" --------------------------------------------------------------------------
" Autocommands - apply syntax and <CR> mapping inside g:howm_dir
" --------------------------------------------------------------------------

augroup howm
  autocmd!
  autocmd BufRead,BufNewFile * call s:setup_buffer()
augroup END

function! s:setup_buffer() abort
  let path = expand('%:p')
  let dir  = fnamemodify(g:howm_dir, ':p')
  if stridx(path, dir) != 0
    return
  endif
  call s:apply_syntax()
  nnoremap <buffer> <CR> :call <SID>follow_link()<CR>
endfunction

" --------------------------------------------------------------------------
" Syntax highlighting
" --------------------------------------------------------------------------

function! s:apply_syntax() abort
  syntax match HowmGoto     /^>>>\s.\+/
  syntax match HowmComeFrom /^<<<\s.\+/
  syntax match HowmTodoDate /\[\d\{4}-\d\{2}-\d\{2}\][+\-!@~.]/
  highlight default link HowmGoto     Statement
  highlight default link HowmComeFrom Identifier
  highlight default link HowmTodoDate Todo
endfunction

" --------------------------------------------------------------------------
" Follow link under cursor
" --------------------------------------------------------------------------

function! s:follow_link() abort
  let line = getline('.')

  " Goto link:      >>> keyword
  let kw = matchstr(line, '^>>>\s*\zs.\+')
  if !empty(kw)
    call s:search(substitute(kw, '\s\+$', '', ''))
    return
  endif

  " Come-from link: <<< keyword
  let kw = matchstr(line, '^<<<\s*\zs.\+')
  if !empty(kw)
    call s:search(substitute(kw, '\s\+$', '', ''))
    return
  endif

  " Not a howm link - fall through to default <CR>
  execute "normal! \<CR>"
endfunction

" --------------------------------------------------------------------------
" Search notes for keyword; files with a come-from anchor appear first
" --------------------------------------------------------------------------

function! s:search(keyword) abort
  let pat   = escape(a:keyword, '/\')
  let files = g:howm_dir . g:howm_glob

  " Pass 1: collect bufnrs of files that have a come-from anchor <<< keyword
  let cf_bufnrs = {}
  try
    silent execute 'vimgrep /<<<\s*' . pat . '/gj ' . files
    for item in getqflist()
      let cf_bufnrs[item.bufnr] = 1
    endfor
  catch /E480/
  endtry

  " Pass 2: find all occurrences of keyword
  let all_items = []
  try
    silent execute 'vimgrep /' . pat . '/gj ' . files
    let all_items = getqflist()
  catch /E480/
  endtry

  if empty(all_items)
    echo 'howm: no matches for "' . a:keyword . '"'
    return
  endif

  " Merge: come-from files first, then everything else
  let first  = filter(copy(all_items), 'has_key(cf_bufnrs, v:val.bufnr)')
  let second = filter(copy(all_items), '!has_key(cf_bufnrs, v:val.bufnr)')
  call setqflist(first + second, 'r')
  copen
endfunction

" --------------------------------------------------------------------------
" List todos relevant to today
" --------------------------------------------------------------------------

function! s:todo() abort
  let today = strftime('%Y-%m-%d')
  let files = g:howm_dir . g:howm_glob

  let raw = []
  try
    silent execute 'vimgrep /\[\d\{4}-\d\{2}-\d\{2}\][+\-!@~.]/gj ' . files
    let raw = getqflist()
  catch /E480/
  endtry

  " Build [priority, date, qf_item] triples; lower priority = shown first
  "   1 = deadline (!)   urgent: show while date >= today
  "   2 = schedule (@)   show on the day
  "   3 = todo (+) / defer (~)   show once date <= today
  "   4 = sink (-)   show only on the day
  let results = []
  for item in raw
    let date = matchstr(item.text, '\[\zs\d\{4}-\d\{2}-\d\{2}\ze\]')
    let type = matchstr(item.text, '\[\d\{4}-\d\{2}-\d\{2}\]\zs[+\-!@~.]')

    if empty(date) || empty(type) || type ==# '.'
      continue
    endif

    let show = 0
    let pri  = 99

    if type ==# '!'
      if date >=# today | let show = 1 | let pri = 1 | endif
    elseif type ==# '@'
      if date ==# today | let show = 1 | let pri = 2 | endif
    elseif type ==# '+' || type ==# '~'
      if date <=# today | let show = 1 | let pri = 3 | endif
    elseif type ==# '-'
      if date ==# today | let show = 1 | let pri = 4 | endif
    endif

    if show
      call add(results, [pri, date, item])
    endif
  endfor

  if empty(results)
    echo 'howm: no todos for today (' . today . ')'
    return
  endif

  call sort(results, {a, b ->
    \ a[0] != b[0] ? a[0] - b[0] :
    \ a[1] <# b[1] ? -1 : a[1] ># b[1] ? 1 : 0})

  call setqflist(map(results, 'v:val[2]'), 'r')
  copen
endfunction

" --------------------------------------------------------------------------
" Create a new timestamped note in g:howm_dir
" --------------------------------------------------------------------------

function! s:new_note() abort
  call mkdir(g:howm_dir, 'p')
  execute 'edit ' . fnameescape(g:howm_dir . strftime('%Y-%m-%d-%H%M%S') . '.txt')
endfunction
