if exists('loaded_oldfiles')
	finish
endif
let loaded_oldfiles = 1

" Line continuation used here
let s:cpo_save = &cpo
set cpo&vim

" Maximum number of entries allowed in the recent files
let s:max_entries = 50
" Vertical split edit
let s:vsplit = 0
" Lock ol when execute grep
let g:lock_oldfiles = 0
" oldfiles用のハイライトグループを定義
if empty(prop_type_get('oldfiles'))
	call prop_type_add('oldfiles', {'highlight': 'Identifier'})
endif

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
		\   'formatter': 'fnamemodify(v:val, ":t")."  (" . v:val . ")"'
        \}

"---------------------------------------------------------------
" OL file
"---------------------------------------------------------------
if has('unix') || has('macunix')
	let s:OL_FILE = $HOME . '/.vim_oldfiles'
else
	if has('win32') && $USERPROFILE != ''
		let s:OL_FILE = $USERPROFILE . '\_vim_oldfiles'
	else
		let s:OL_FILE = $VIM . '/_vim_oldfiles'
	endif
endif

"---------------------------------------------------------------
" Selected handler
"---------------------------------------------------------------
function! s:onSelect(winid, result) abort
	if a:result <= 0 || len(s:OldFiles) <= 0 | return | endif

	let fname = s:OldFiles[a:result - 1]
	if empty(fname) | return | endif

	" If already open, jump to it or Edit the file
	let winnum = bufwinnr('^' . fname . '$')
	if winnum != -1
		exe winnum . 'wincmd w'
	else
		exe printf('%s %s', (s:vsplit ? 'vsplit' : 'edit'), s:escape_filename(fname))
	endif
endfunction

"---------------------------------------------------------------
" Open popup window
"---------------------------------------------------------------
function! s:open_popup() abort
	" 「xxxxx.c (/xxx/xxx/xxx.c)」に成形
	let oldfiles = map(copy(s:OldFiles), g:OL_filename_format.formatter)

	" 辞書に変換
	let output = []
	for v in oldfiles
		call add(output, {'text':v, 'props':[#{col: 1, length: stridx(v, ' (')-1, type: "oldfiles"}]})
	endfor

	let opts = {
			\ 'title': ' oldfiles ',
			\ 'border': [1,1,1,1],
			\ 'padding': [1,2,1,2],
			\ 'maxheight': 20,
			\ 'minwidth': &columns-20,
			\ 'mapping': v:false,
			\ 'wrap': v:false,
			\ 'callback': function('s:onSelect'),
			\ 'filter': function('s:menu_filter')
			\ }

	const winid = popup_menu(output, opts)
endfunction

"-------------------------------------------------------
" Update popup menu
"-------------------------------------------------------
function! s:update_popup(winid) abort
	" 「xxxxx.c (/xxx/xxx/xxx.c)」に成形
	let oldfiles = map(copy(s:OldFiles), g:OL_filename_format.formatter)

	" 辞書に変換
	let output = []
	for v in oldfiles
		call add(output, {'text':v, 'props':[#{col: 1, length: stridx(v, ' (')-1, type: "oldfiles"}]})
	endfor

	" ポップアップメニューの内容を更新
	call popup_settext(a:winid, output)

	" カーソルを先頭に戻す
    call win_execute(a:winid, 'normal! gg')

	" 再表示(コマンド行をクリアしたいため)
	redraw!
endfunction

"---------------------------------------------------------------
" menu filter
"---------------------------------------------------------------
function! s:menu_filter(winid, key) abort
	if a:key ==# 'q'		" 終了
		call popup_close(a:winid, -1)
		return 1

	elseif a:key ==# 'l' || a:key ==# 'v'	" 開く
		let s:vsplit = (a:key ==# 'v' ? 1 : 0)
		call popup_close(a:winid, getcurpos(a:winid)[1])
		return 1

	elseif a:key ==# 's'	" 先頭の1文字でフィルタリング
		call s:filter_by_first_character()
		call s:update_popup(a:winid)

	elseif a:key ==# '/'	" 検索でフィルタリング
		call s:filter_by_search_pattern()
		call s:update_popup(a:winid)

	elseif a:key ==# '!'	" リンク切れのファイルを履歴から削除
		call s:command(a:winid)
		call s:update_popup(a:winid)

   	endif

	return popup_filter_menu(a:winid, a:key)
endfunction

"---------------------------------------------------------------
" filter by first character
"---------------------------------------------------------------
function! s:filter_by_first_character() abort
	call s:load_oldfiles()
	let char = s:getchar("Filtering character: ")
	if char =~ "[a-z0-9._]"
		call filter(s:OldFiles, 'fnamemodify(v:val, ":t")[0] ==? char')
	endif
endfunction

"---------------------------------------------------------------
" filter by search pattern
"---------------------------------------------------------------
function! s:filter_by_search_pattern() abort
	call s:load_oldfiles()
	let pattern = input('/')
	if !empty(pattern)
		call filter(s:OldFiles, 'v:val =~ pattern')
	endif
endfunction

"---------------------------------------------------------------
" command mode
"---------------------------------------------------------------
function! s:command(winid) abort
	let char = s:getchar('[c:clean, d:delete]: ')

	if char ==# 'c'
		call s:remove_non_existing_item_from_oldfiles()

	elseif char ==# 'd'
		call s:delete_item_from_oldfiles(getcurpos(a:winid)[1])

	endif
endfunction

"---------------------------------------------------------------
" remove_non_existing_item_from_oldfiles
"---------------------------------------------------------------
function! s:remove_non_existing_item_from_oldfiles() abort
	call s:load_oldfiles()
	let temp = copy(s:OldFiles)

	" リンクが有効なものでフィルタリング
	call filter(temp, 'filereadable(v:val)')

	" 削除確認
	if input(printf("%d files remove ? [y/n] ", len(s:OldFiles) - len(temp))) ==# "y"
		let s:OldFiles = copy(temp)
		call writefile(s:OldFiles, s:OL_FILE)
	endif
endfunction

"---------------------------------------------------------------
" load oldfiles
"---------------------------------------------------------------
function! s:load_oldfiles() abort
	let s:OldFiles = filereadable(s:OL_FILE) ? readfile(s:OL_FILE) : []
endfunction

"---------------------------------------------------------------
" escape filename
"---------------------------------------------------------------
function! s:escape_filename(fname) abort
	if exists("*fnameescape")
		return fnameescape(a:fname)
	else
		let esc_filename_chars = ' *?[{`$%#"|!<>();&' . "'\t\n"
		return escape(a:fname, esc_filename_chars)
	endif
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

" --------------------------------------------------------------
" warn_msg
" --------------------------------------------------------------
function! s:warn_msg(msg) abort
	echohl WarningMsg | echo a:msg | echohl None
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
endfunction

" --------------------------------------------------------------
" delete_item_from_oldfiles
" --------------------------------------------------------------
function s:delete_item_from_oldfiles(lnum)
	" 削除する履歴を取得
	let item = s:OldFiles[a:lnum - 1]

	" 履歴をロードし直して、削除対象と一致する履歴を除外する
	call s:load_oldfiles()
	call filter(s:OldFiles, 'v:val != item')

	" 履歴をセーブ
	call writefile(s:OldFiles, s:OL_FILE)
endfunction

" --------------------------------------------------------------
" OL
" --------------------------------------------------------------
function! s:OL() abort
	" Quickfixウィンドウにはバッファをオープンさせないため、Quickfixから起動時はここで終了させる
	if &buftype == 'quickfix'
		echohl WarningMsg | echo "Cannot executed with quickfix window" | echohl None
		return
	endif

	" 履歴をs:OldFilesに読み込む
	call s:load_oldfiles()
	if empty(s:OldFiles)
		call s:warn_msg('Old files list is empty')
		return
	endif

	call s:open_popup()
endfunction

" --------------------------------------------------------------
" Command to open the OL window
" --------------------------------------------------------------
autocmd BufRead * call s:add_item(expand('<abuf>'))
autocmd BufNewFile * call s:add_item(expand('<abuf>'))
autocmd BufWritePost * call s:add_item(expand('<abuf>'))
autocmd QuickFixCmdPre *vimgrep* let g:lock_oldfiles = 1
autocmd QuickFixCmdPost *vimgrep* let g:lock_oldfiles = 0

command! -nargs=? OL call s:OL()

" restore 'cpo'
let &cpo = s:cpo_save
unlet s:cpo_save

