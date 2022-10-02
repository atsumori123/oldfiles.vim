if exists('loaded_ol')
	finish
endif
let loaded_ol = 1

" Line continuation used here
let s:cpo_save = &cpo
set cpo&vim

" Maximum number of entries allowed in the recent files
let s:OL_max_entries = 50
" Height of the window
let s:OL_window_height = 16
" OL buffer name
let s:OL_buf_name = '-Old files-'
" Lock ol when execute grep
let s:OL_list_locked = 0
" Use vim_ol_file
let s:OL_use_ol_file = 1
" Use FZF
let s:OL_use_fzf = exists('*fzf#run') ? 0 : 0

" --------------------------------------------------------------
" Format of the file names displayed in the OL window.
" The default is to display the filename followed by the complete path to the
" file in parenthesis. This variable controls the expressions used to format
" and parse the path. This can be changed to display the filenames in a
" different format. The 'formatter' specifies how to split/format the filename
" and 'parser' specifies how to read the filename back; 'syntax' matches the
" part to be highlighted.
" --------------------------------------------------------------
let g:OL_filename_format = {
        \   'formatter': 'fnamemodify(v:val, ":t") . " (" . v:val . ")"',
        \   'parser': '(\zs.*\ze)',
        \   'syntax': '^.\{-}\ze('
        \}

" --------------------------------------------------------------
" OL file
" --------------------------------------------------------------
if s:OL_use_ol_file
	if has('unix') || has('macunix')
		let s:OL_FILE = $HOME . '/.vim_ol_files'
	else
		if has('win32') && $USERPROFILE != ''
			let s:OL_FILE = $USERPROFILE . '\_vim_ol_files'
		else
			let s:OL_FILE = $VIM . '/_vim_ol_files'
		endif
	endif
endif

" --------------------------------------------------------------
" OL_load_from_oldfiles
" --------------------------------------------------------------
function! s:OL_load_from_oldfiles() abort
	let s:OL_files = []

	for l:b in range(1, bufnr('$'))
		if len(s:OL_files) >= s:OL_max_entries | break | endif

		" skip non-existing, unnamed and special buffers.
		if empty(bufname(l:b)) || !empty(getbufvar(l:b, '&buftype'))
			continue
		endif

		" Convert to full path filename. check readable
		let fname = fnamemodify(bufname(l:b), ':p')
		if !filereadable(fname)
			continue
		endif

		" Add to list
		call add(s:OL_files, fname)
	endfor

	for l:f in v:oldfiles
		if len(s:OL_files) >= s:OL_max_entries | break | endif

		" Convert to full path filename. check readable
		let fname = expand(l:f)
		if !filereadable(fname)
			continue
		endif

		" Duplicate check
		let fname = s:OL_escape_filename(fname)
		call filter(s:OL_files, 'v:val !=# fname')

		" Add to list
		call add(s:OL_files, fname)
	endfor
endfunction

" --------------------------------------------------------------
" OL_load_from_ol_file
" --------------------------------------------------------------
function! s:OL_load_from_ol_file() abort
	let s:OL_files = filereadable(s:OL_FILE) ? readfile(s:OL_FILE) : []
endfunction

" --------------------------------------------------------------
" OL_escape_filename
" --------------------------------------------------------------
function! s:OL_escape_filename(fname) abort
	let esc_filename_chars = ' *?[{`$%#"|!<>();&' . "'\t\n"

	if exists("*fnameescape")
		return fnameescape(a:fname)
	else
		return escape(a:fname, esc_filename_chars)
	endif
endfunction

" --------------------------------------------------------------
" OL_selected
" --------------------------------------------------------------
function! s:OL_selected(open_cmd) abort
	" Get selected line
	let fname = getline(".")

	" Automatically close the OL window
	silent! close

	if fname == '' | return | endif

	" The text in the OL window contains the filename in parenthesis
	let file = matchstr(fname, g:OL_filename_format.parser)

	" If already open, jump to it or Edit the file
	let winnum = bufwinnr('^' . file . '$')
	if winnum != -1
		exe winnum . 'wincmd w'
	else
		" Return to recent window and open
		exe 'wincmd p'
		exe printf('%s %s', a:open_cmd, s:OL_escape_filename(file))
	endif
endfunction

"---------------------------------------------------------------
" OL_remove_non_existing_files
"---------------------------------------------------------------
function! s:OL_remove_non_existing_files() abort
	call s:OL_load_from_ol_file()
	let old_num = len(s:OL_files)
	call filter(s:OL_files, 'filereadable(v:val)')
	let yesno = input(printf("%d files remove ? [y/n] ", old_num - len(s:OL_files)))
	if yesno !=? "y" | return | endif
	call writefile(s:OL_files, s:OL_FILE)
	call OL_draw()
endfunction

"---------------------------------------------------------------
" OL_skip_cursor
"---------------------------------------------------------------
function! s:OL_skip_cursor() abort
	let key = getcharstr()
	if key == "" | return | endif

	call s:OL_load_from_ol_file()
	if key =~ "[a-z._]"
		call filter(s:OL_files, 'fnamemodify(v:val, ":t")[0] ==? key')
	endif
	call s:OL_draw()
endfunction

" --------------------------------------------------------------
" OL_selected_fzf
" --------------------------------------------------------------
function! s:OL_selected_fzf(fname) abort
	let l:fname = s:OL_escape_filename(a:fname)

	" If already open, jump to it or Edit the file
	let winnum = bufwinnr('^' . a:fname . '$')
	if winnum != -1
		execute winnum . 'wincmd w'
	else
		execute 'edit ' . l:fname
	endif
endfunction

" --------------------------------------------------------------
" OL_warn_msg
" --------------------------------------------------------------
function! s:OL_warn_msg(msg) abort
	echohl WarningMsg | echo a:msg | echohl None
endfunction

" --------------------------------------------------------------
" OL_draw
" --------------------------------------------------------------
function! s:OL_draw() abort
	setlocal modifiable

	" Delete the contents of the buffer to the black-hole register
	silent! %delete _

	let output = map(s:OL_files, g:OL_filename_format.formatter)
	silent! 0put =output

	" Delete the empty line at the end of the buffer
	silent! $delete _

	" Move the cursor to the beginning of the file
	normal! gg

	setlocal nomodifiable
endfunction

" --------------------------------------------------------------
" OL_open
" --------------------------------------------------------------
function! s:OL_open() abort
	let winnum = bufwinnr(s:OL_buf_name)
	if winnum != -1
		" Already in the window, jump to it
		exe winnum . 'wincmd w'
	else
		" Open a new window at the bottom
		exe 'silent! botright '.s:OL_window_height.'split '.s:OL_buf_name
	endif

	setlocal buftype=nofile
	setlocal bufhidden=delete
	setlocal noswapfile
	setlocal nobuflisted
	setlocal nowrap
	setlocal winfixheight winfixwidth
	setlocal filetype=OL

	" Setup the cpoptions properly for the maps to work
	let old_cpoptions = &cpoptions
	set cpoptions&vim

	" Create mappings to select and edit a file from the OL list
	nnoremap <buffer> <silent> <CR> :call <SID>OL_selected('edit')<CR>
	nnoremap <buffer> <silent> l :call <SID>OL_selected('edit')<CR>
	nnoremap <buffer> <silent> v :call <SID>OL_selected('vsplit')<CR>
	nnoremap <buffer> <silent> f :call <SID>OL_skip_cursor()<CR>
	nnoremap <buffer> <silent> q :close<CR>
	if s:OL_use_ol_file
		nnoremap <buffer> <silent> d :<C-U>call <SID>OL_delete_from_list()<CR>
		nnoremap <buffer> <silent> clear :<C-U>call <SID>OL_remove_non_existing_files()<CR>
	endif

	call s:OL_draw()

	" Restore the previous cpoptions settings
	let &cpoptions = old_cpoptions

	" Add syntax highlighting for the file names
	exe "syntax match OLFileName '" . g:OL_filename_format.syntax . "'"
	highlight default link OLFileName Identifier
endfunction

" --------------------------------------------------------------
" OL_add
" --------------------------------------------------------------
function! s:OL_add(acmd_bufnr) abort
	if s:OL_list_locked
		" OL list is currently locked
		return
	endif

	" Get the full path to the filename
	let fname = fnamemodify(bufname(a:acmd_bufnr + 0), ':p')
	if fname == '' | return | endif

	" Skip temporary buffers with buftype set.
	" The buftype is set for buffers used by plugins.
	if &buftype != '' | return | endif

	" If file is readable, then skip
	if !filereadable(fname) | return | endif

	" Load the latest OL file list
	call s:OL_load_from_ol_file()

	" Remove the new file name from the existing OL list (if already present)
	call filter(s:OL_files, 'v:val !=# fname')

	" Add the new file list to the beginning of the updated old file list
	call insert(s:OL_files, fname, 0)

	" Trim the list
	if len(s:OL_files) > s:OL_max_entries
		call remove(s:OL_files, s:OL_max_entries, -1)
	endif

	" Save the updated OL list
	call writefile(s:OL_files, s:OL_FILE)

	" If the OL window is open, update the displayed OL list
	if bufwinnr(s:OL_buf_name) != -1
		let cur_winnr = winnr()
		call s:OL_open()
		exe cur_winnr . 'wincmd w'
	endif
endfunction

" --------------------------------------------------------------
" OL_delete_from_list
" --------------------------------------------------------------
function s:OL_delete_from_list()
	let backup = s:OL_files
	call s:OL_load_from_ol_file()
	call filter(s:OL_files, 'v:val != matchstr(getline("."), g:OL_filename_format.parser)')
	setlocal modifiable
	del _
	setlocal nomodifiable
	call writefile(s:OL_files, s:OL_FILE)
	let s:OL_files = backup
endfunction

" --------------------------------------------------------------
" OL
" --------------------------------------------------------------
function! s:OL(...) abort
	" Load the old files
	if s:OL_use_ol_file
		call s:OL_load_from_ol_file()
	else
		call s:OL_load_from_oldfiles()
	endif

	" OL list empty check
	if empty(s:OL_files)
		call s:OL_warn_msg('Old files list is empty')
		return
	endif

	" Filtering
	if a:0 != 0
		call filter(s:OL_files, 'v:val =~# a:1')
		if len(s:OL_files) == 0
			call s:OL_warn_msg("Old files list doesn't contain files matching " . a:1)
			return
		endif
	endif

	if s:OL_use_fzf
		call fzf#run(fzf#wrap({'source' : s:OL_files,
			\ 'sink' : function('s:OL_selected_fzf'),
			\ 'options' : '--color=fg+:2',
			\ 'down' : '25%'}, 0))
	else
		call s:OL_open()
	endif
endfunction

" --------------------------------------------------------------
" Command to open the OL window
" --------------------------------------------------------------
if s:OL_use_ol_file
	autocmd BufRead * call s:OL_add(expand('<abuf>'))
	autocmd BufNewFile * call s:OL_add(expand('<abuf>'))
	autocmd BufWritePost * call s:OL_add(expand('<abuf>'))
	autocmd QuickFixCmdPre *vimgrep* let s:OL_list_locked = 1
	autocmd QuickFixCmdPost *vimgrep* let s:OL_list_locked = 0
endif

command! -nargs=? OL call s:OL(<f-args>)

" restore 'cpo'
let &cpo = s:cpo_save
unlet s:cpo_save

