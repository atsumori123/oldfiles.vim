if exists('loaded_ol')
	finish
endif
let loaded_ol = 1

" Line continuation used here
let s:cpo_save = &cpo
set cpo&vim

" Maximum number of entries allowed in the recent files
let s:max_entries = 50
" Height of the window
let s:window_height = 16
" OL buffer name
let s:buf_name = '-Old files-'
" Lock ol when execute grep
let g:lock_oldfiles = 0
" Use vim_olfile
let s:use_olfile = 1
" Use FZF
let s:use_fzf = exists('*fzf#run') ? 0 : 0

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
if s:use_olfile
	if has('unix') || has('macunix')
		let s:OL_FILE = $HOME . '/.vim_oldfiles'
	else
		if has('win32') && $USERPROFILE != ''
			let s:OL_FILE = $USERPROFILE . '\_vim_oldfiles'
		else
			let s:OL_FILE = $VIM . '/_vim_oldfiles'
		endif
	endif
endif

" --------------------------------------------------------------
" load_oldfiles_from_oldfiles
" --------------------------------------------------------------
function! s:load_oldfiles_from_oldfiles() abort
	let s:OldFiles = []

	for l:b in range(1, bufnr('$'))
		if len(s:OldFiles) >= s:max_entries | break | endif

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
		call add(s:OldFiles, fname)
	endfor

	for l:f in v:oldfiles
		if len(s:OldFiles) >= s:max_entries | break | endif

		" Convert to full path filename. check readable
		let fname = expand(l:f)
		if !filereadable(fname)
			continue
		endif

		" Duplicate check
		let fname = s:escape_filename(fname)
		call filter(s:OldFiles, 'v:val !=# fname')

		" Add to list
		call add(s:OldFiles, fname)
	endfor
endfunction

" --------------------------------------------------------------
" load_oldfiles_from_olfile
" --------------------------------------------------------------
function! s:load_oldfiles_from_olfile() abort
	let s:OldFiles = filereadable(s:OL_FILE) ? readfile(s:OL_FILE) : []
endfunction

" --------------------------------------------------------------
" load_oldfiles
" --------------------------------------------------------------
function! s:load_oldfiles() abort
	if s:use_olfile
		call s:load_oldfiles_from_olfile()
	else
		call s:load_oldfiles_from_oldfiles()
	endif
endfunction

" --------------------------------------------------------------
" escape_filename
" --------------------------------------------------------------
function! s:escape_filename(fname) abort
	if exists("*fnameescape")
		return fnameescape(a:fname)
	else
		let esc_filename_chars = ' *?[{`$%#"|!<>();&' . "'\t\n"
		return escape(a:fname, esc_filename_chars)
	endif
endfunction

" --------------------------------------------------------------
" select_item
" --------------------------------------------------------------
function! s:select_item(open_cmd) abort
	let fname = getline(".")

	" Automatically close the window
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
		exe printf('%s %s', a:open_cmd, s:escape_filename(file))
	endif
endfunction

"---------------------------------------------------------------
" remove_non_existing_item_from_oldfiles
"---------------------------------------------------------------
function! s:remove_non_existing_item_from_oldfiles() abort
	call s:load_oldfiles()
	let old_num = len(s:OldFiles)
	call filter(s:OldFiles, 'filereadable(v:val)')
	let yesno = input(printf("%d files remove ? [y/n] ", old_num - len(s:OldFiles)))
	if yesno !=? "y" | return | endif
	call writefile(s:OldFiles, s:OL_FILE)
	call s:draw_buffer()
endfunction


"---------------------------------------------------------------
" get character
"---------------------------------------------------------------
function! s:getchar(msg)
	" Workaround for https://github.com/osyo-manga/vital-over/issues/53
	echo a:msg

	try
		let char = call('getchar', a:000)
	catch /^Vim:Interrupt$/
		let char = 3 " <C-c>
	endtry
	if char == 27 || char == 3
		" Escape or <C-c> key pressed
		redraw
		echo "Canceled"
		return ''
	endif

	redraw
	echo ""
	return	nr2char(char)
endfunction

"---------------------------------------------------------------
" filtering_item
"---------------------------------------------------------------
function! s:filtering_item() abort
	let char = s:getchar("Filtering character: ")
	if char == ""
		return
	end

	call s:load_oldfiles()
	if char =~ "[a-z0-9._]"
		call filter(s:OldFiles, 'fnamemodify(v:val, ":t")[0] ==? char')
	endif
	call s:draw_buffer()
endfunction

" --------------------------------------------------------------
" select_item_fzf
" --------------------------------------------------------------
function! s:select_item_fzf(fname) abort
	let l:fname = s:escape_filename(a:fname)

	" If already open, jump to it or Edit the file
	let winnum = bufwinnr('^' . a:fname . '$')
	if winnum != -1
		execute winnum . 'wincmd w'
	else
		execute 'edit ' . l:fname
	endif
endfunction

" --------------------------------------------------------------
" warn_msg
" --------------------------------------------------------------
function! s:warn_msg(msg) abort
	echohl WarningMsg | echo a:msg | echohl None
endfunction

" --------------------------------------------------------------
" draw_buffer
" --------------------------------------------------------------
function! s:draw_buffer() abort
	setlocal modifiable

	" Delete the contents of the buffer to the black-hole register
	silent! %delete _

	let output = map(s:OldFiles, g:OL_filename_format.formatter)
	silent! 0put =output

	" Delete the empty line at the end of the buffer
	silent! $delete _

	" Move the cursor to the beginning of the file
	normal! gg

	setlocal nomodifiable
endfunction

" --------------------------------------------------------------
" open_buffer
" --------------------------------------------------------------
function! s:open_buffer() abort
	let winnum = bufwinnr(s:buf_name)
	if winnum != -1
		" Already in the window, jump to it
		exe winnum . 'wincmd w'
	else
		" Open a new window at the bottom
		exe 'silent! botright '.s:window_height.'split '.s:buf_name
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
	nnoremap <buffer> <silent> <CR> :call <SID>select_item('edit')<CR>
	nnoremap <buffer> <silent> l :call <SID>select_item('edit')<CR>
	nnoremap <buffer> <silent> v :call <SID>select_item('vsplit')<CR>
	nnoremap <buffer> <silent> s :call <SID>filtering_item()<CR>
	nnoremap <buffer> <silent> q :close<CR>:execute "wincmd p"<CR>
	if s:use_olfile
		nnoremap <buffer> <silent> dd :<C-U>call <SID>delete_item_from_oldfiles()<CR>
		nnoremap <buffer> <silent> clean :<C-U>call <SID>remove_non_existing_item_from_oldfiles()<CR>
	endif

	call s:draw_buffer()

	" Restore the previous cpoptions settings
	let &cpoptions = old_cpoptions

	" Add syntax highlighting for the file names
	exe "syntax match OLFileName '" . g:OL_filename_format.syntax . "'"
	highlight default link OLFileName Identifier
endfunction

" --------------------------------------------------------------
" add_item
" --------------------------------------------------------------
function! s:add_item(acmd_bufnr) abort
	" oldfiles list is currently locked
	if g:lock_oldfiles | return | endif

	" Get the full path to the filename
	let fname = fnamemodify(bufname(a:acmd_bufnr + 0), ':p')
	if fname == '' | return | endif

	" Skip temporary buffers with buftype set.
	" The buftype is set for buffers used by plugins.
	if &buftype != '' | return | endif

	" If file is readable, then skip
	if !filereadable(fname) | return | endif

	" Load the latest oldfiles list
	call s:load_oldfiles()

	" Remove the new file name from the existing list (if already present)
	call filter(s:OldFiles, 'v:val !=# fname')

	" Add the new file list to the beginning of the updated old file list
	call insert(s:OldFiles, fname, 0)

	" Trim the list
	if len(s:OldFiles) > s:max_entries
		call remove(s:OldFiles, s:max_entries, -1)
	endif

	" Save the updated oldfiles list
	call writefile(s:OldFiles, s:OL_FILE)

	" If the OL window is open, update the displayed oldfiles list
	if bufwinnr(s:buf_name) != -1
		let cur_winnr = winnr()
		call s:open_buffer()
		exe cur_winnr . 'wincmd w'
	endif
endfunction

" --------------------------------------------------------------
" delete_item_from_oldfiles
" --------------------------------------------------------------
function s:delete_item_from_oldfiles()
	let backup = s:OldFiles
	call s:load_oldfiles()
	call filter(s:OldFiles, 'v:val != matchstr(getline("."), g:OL_filename_format.parser)')
	setlocal modifiable
	del _
	setlocal nomodifiable
	call writefile(s:OldFiles, s:OL_FILE)
	let s:OldFiles = backup
endfunction

" --------------------------------------------------------------
" OL
" --------------------------------------------------------------
function! s:OL(...) abort
	if &buftype == 'quickfix'
		echohl WarningMsg | echo "Cannot executed with quickfix window" | echohl None
		return
	endif

	call s:load_oldfiles()
	if empty(s:OldFiles)
		call s:warn_msg('Old files list is empty')
		return
	endif

	" Filtering
	if a:0 != 0
		call filter(s:OldFiles, 'v:val =~# a:1')
		if len(s:OldFiles) == 0
			call s:warn_msg("Old files list doesn't contain files matching " . a:1)
			return
		endif
	endif

	if s:use_fzf
		call fzf#run(fzf#wrap({'source' : s:OldFiles,
			\ 'sink' : function('s:select_item_fzf'),
			\ 'options' : '--color=fg+:2',
			\ 'down' : '25%'}, 0))
	else
		call s:open_buffer()
	endif
endfunction

" --------------------------------------------------------------
" Command to open the OL window
" --------------------------------------------------------------
if s:use_olfile
	autocmd BufRead * call s:add_item(expand('<abuf>'))
	autocmd BufNewFile * call s:add_item(expand('<abuf>'))
	autocmd BufWritePost * call s:add_item(expand('<abuf>'))
	autocmd QuickFixCmdPre *vimgrep* let g:lock_oldfiles = 1
	autocmd QuickFixCmdPost *vimgrep* let g:lock_oldfiles = 0
endif

command! -nargs=? OL call s:OL(<f-args>)

" restore 'cpo'
let &cpo = s:cpo_save
unlet s:cpo_save

