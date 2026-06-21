" Line continuation used here
let s:cpo_save = &cpo
set cpo&vim

if !has('nvim')
	" 複数キーによるコンビネーション用
	let s:last_key = ''
	" 前回打鍵したときの時間
	let s:last_time = [0, 0] " [seconds, microseconds]
	" oldfiles用のハイライトグループを定義
	if empty(prop_type_get('oldfiles'))
		call prop_type_add('oldfiles', {'highlight': 'Identifier'})
	endif
endif

" Lock ol when execute grep
let g:lock_oldfiles = 0

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
" warn_msg
"---------------------------------------------------------------
function! s:warn_msg(msg) abort
	echohl WarningMsg | echo a:msg | echohl None
endfunction

"---------------------------------------------------------------
" 履歴の読み込み
"---------------------------------------------------------------
function! s:load_oldfiles() abort
	return filereadable(s:OL_FILE) ? readfile(s:OL_FILE) : []
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
" 出力形式に変換
"---------------------------------------------------------------
function! s:make_output(oldfiles) abort
	if has('nvim')
		let output = map(copy(a:oldfiles), '" " . fnamemodify(v:val, ":t")."  (" . v:val . ")"')
	else
		let list = map(copy(a:oldfiles), 'fnamemodify(v:val, ":t")."  (" . v:val . ")"')
		let output = []
		for v in list
			call add(output, {'text':v, 'props':[#{col: 1, length: stridx(v, ' (')-1, type: "oldfiles"}]})
		endfor
	endif
	return output
endfunction

"---------------------------------------------------------------
" get character
"---------------------------------------------------------------
function! s:get_char(msg)
	echo a:msg
	try
		let char_raw = getchar()
		let char = (type(char_raw) == type(0)) ? nr2char(char_raw) : char_raw
	catch /^Vim:Interrupt$/
		let char = "\<ESC>"
	endtry

	redraw
	return char == "\<ESC>" ? "" : char
endfunction

"---------------------------------------------------------------
" Selected handler
"---------------------------------------------------------------
function! s:on_select(winid, result) abort
	if a:result == -1
		if has('nvim') | close | endif

	else
		" 選択項目を取得
		let fname = win_execute(a:winid, 'echo getline(".")')
		let fname = matchstr(fname, '(\zs.*\ze)')
		if has('nvim') | close | endif

		" If already open, jump to it or Edit the file
		let winnum = bufwinnr('^' . fname . '$')
		if winnum != -1
			exe winnum . 'wincmd w'
		else
			exe printf('%s %s', (a:result ? 'vsplit' : 'edit'), s:escape_filename(fname))
		endif
	endif

	unlet s:OldFiles
endfunction

"-------------------------------------------------------
" Update popup menu
"-------------------------------------------------------
function! s:update_text(winid, oldfiles, restore_cursor) abort
	" カーソル位置(行)を取得
	let lnum = getcurpos(a:winid)[1]

	" 「xxxxx.c (/xxx/xxx/xxx.c)」に成形
	let output = s:make_output(a:oldfiles)

	if has('nvim')
		" 変更禁止解除→全行消去→描画→変更禁止
		setlocal modifiable
		call nvim_buf_set_lines(0, 0, -1, v:false, output)
		setlocal nomodifiable
	else
		" ポップアップメニューの内容を更新
		call popup_settext(a:winid, output)
	endif

	" カーソル位置の設定
	if a:restore_cursor
		" 復元
		call win_execute(a:winid, 'call cursor(min([lnum, len(output)]), 1)')
	else
		" 先頭
		call win_execute(a:winid, 'normal! gg0')
	endif

	" 再表示(コマンド行をクリアしたいため)
	redraw!
endfunction

"---------------------------------------------------------------
" filter by first character
"---------------------------------------------------------------
function! s:filter_by_first_character(winid) abort
	let char = s:get_char("Filtering character: ")
	if char =~ "[a-z0-9._]"
		let oldfiles = filter(copy(s:OldFiles), 'fnamemodify(v:val, ":t")[0] ==? char')
		call s:update_text(a:winid, oldfiles, 0)
	else
		call s:update_text(a:winid, s:OldFiles, 0)
	endif
	redraw
	echo ""
endfunction

"---------------------------------------------------------------
" filter by search pattern
"---------------------------------------------------------------
function! s:filter_by_search_pattern(winid) abort
	let pattern = input('/')
	if !empty(pattern)
		let oldfiles = filter(copy(s:OldFiles), 'v:val =~ pattern')
		call s:update_text(a:winid, oldfiles, 0)
	else
		call s:update_text(a:winid, s:OldFiles, 0)
	endif
	redraw
	echo ""
endfunction

"---------------------------------------------------------------
" delete_item_from_oldfiles
"---------------------------------------------------------------
function s:delete_item_from_oldfiles(winid)
	" 選択項目を取得
	let fname = win_execute(a:winid, 'echo getline(".")')
	let fname = matchstr(fname, '(\zs.*\ze)')

	" 削除対象と一致する履歴を除外する
	call filter(s:OldFiles, 'v:val != fname')
	call s:update_text(a:winid, s:OldFiles, 1)

	" 履歴をセーブ
	call writefile(s:OldFiles, s:OL_FILE)
endfunction

"---------------------------------------------------------------
" remove_non_existing_item_from_oldfiles
"---------------------------------------------------------------
function! s:remove_non_existing_item_from_oldfiles(winid) abort
	" リンクが有効なものでフィルタリング
	let temp = filter(copy(s:OldFiles), 'filereadable(v:val)')

	" 削除確認してから反映
	if input(printf("%d files remove ? [y/n] ", len(s:OldFiles) - len(temp))) ==# "y"
		let s:OldFiles = copy(temp)
		call s:update_text(a:winid, s:OldFiles, 0)
		call writefile(s:OldFiles, s:OL_FILE)
	else
		redraw!
	endif
endfunction

if has('nvim')
"---------------------------------------------------------------
" Open popup window
"---------------------------------------------------------------
function! s:open_popup() abort
	" create buffer (listed=false, scratch(使い捨て)=true)
	let bufnr = nvim_create_buf(v:false, v:true)

	" create floating window
	let width = &columns - 30
	let height = 20
	let opts =  {
			\ 'title':		" oldfiles (l:Open, f:Filter, /:Search, rm:Remove selected item, rn:Remove non exists) ",
			\ 'style':		"minimal",
			\ 'relative':	"editor",
			\ 'height':		height,
			\ 'width':		width,
			\ 'col':		float2nr(trunc((&columns - width) / 2)) - 1,
			\ 'row':		float2nr(trunc((&lines - height) / 2)) - 1,
			\ 'border':		"single"
			\ }
	let winid = nvim_open_win(bufnr, v:true, opts)

	" 履歴を表示
	call s:update_text(winid, s:OldFiles, 0)

	" set buffer option
	setlocal bufhidden=wipe
	setlocal nomodifiable
	setlocal noswapfile
	setlocal nowrap

	" set highlight
	syntax match OLFileName '^.\{-}\ze('
	highlight default link OLFileName Identifier
	
	" キーマップ
	nnoremap <buffer> <silent> <CR> :call <SID>on_select(win_getid(), 0)<CR>
	nnoremap <buffer> <silent> l    :call <SID>on_select(win_getid(), 0)<CR>
	nnoremap <buffer> <silent> v    :call <SID>on_select(win_getid(), 2)<CR>
	nnoremap <buffer> <silent> f    :call <SID>filter_by_first_character(win_getid())<CR>
	nnoremap <buffer> <silent> /    :call <SID>filter_by_search_pattern(win_getid())<CR>
	nnoremap <buffer> <silent> rm   :call <SID>delete_item_from_oldfiles(win_getid())<CR>
	nnoremap <buffer> <silent> rn   :call <SID>remove_non_existing_item_from_oldfiles(win_getid())<CR>
	nnoremap <buffer> <silent> q    :call <SID>on_select(win_getid(), -1)<CR>
endfunction

else
"---------------------------------------------------------------
" popup filter
"---------------------------------------------------------------
function! s:popup_filter(winid, key) abort
	let now = reltime()

	" 前回の打鍵からの経過時間をミリ秒で計算
	" reltimefloat は秒単位（小数）で返すため 1000 倍する
	let elapsed = reltimefloat(reltime(s:last_time, l:now)) * 1000

	" 設定値（timeoutlen）を超えていたらバッファをクリア
	if elapsed > &timeoutlen
		let s:last_key = ''
	endif

	" 今回の打鍵時刻を記録
	let s:last_time = now

	if a:key ==# 'q'			" 終了
		call popup_close(a:winid, -1)
		let s:last_key = ''
		return 1

	elseif a:key =~ '^[l|v]$' || a:key ==# "\<CR>"	" 開く
		call popup_close(a:winid, (a:key == 'v' ? 1 : 0))
		let s:last_key = ''
		return 1

	elseif a:key ==# 'f'		" 先頭の1文字でフィルタリング
		call s:filter_by_first_character(a:winid)
		let s:last_key = ''
		return 1

	elseif a:key ==# '/'		" 検索でフィルタリング
		call s:filter_by_search_pattern(a:winid)
		let s:last_key = ''
		return 1

	elseif s:last_key ==# 'r' && a:key ==# 'm'	" 履歴の削除
		call s:delete_item_from_oldfiles(a:winid)
		let s:last_key = ''
		return 1

	elseif s:last_key ==# 'r' && a:key ==# 'n'	" リンク切れのファイルを履歴から削除
		call s:remove_non_existing_item_from_oldfiles(a:winid)
		let s:last_key = ''
		return 1

   	endif

	let s:last_key = a:key	

	return popup_filter_menu(a:winid, a:key)
endfunction

"---------------------------------------------------------------
" Open popup window
"---------------------------------------------------------------
function! s:open_popup() abort
	" 「xxxxx.c (/xxx/xxx/xxx.c)」に成形
	let output = s:make_output(s:OldFiles)

	let opts = {
			\ 'title':			' oldfiles (l:Open, f:Filter, /:Search, rm:Remove selected item, rn:Remove non exists) ',
			\ 'border':			[1,1,1,1],
			\ 'borderchars':	has('unix') ? [] : ['─','│','─','│','┌','┐','┘','└'],
			\ 'padding':		[1,2,1,2],
			\ 'maxheight':		20,
			\ 'minwidth':		&columns-30,
			\ 'mapping':		v:false,
			\ 'wrap':			v:false,
			\ 'callback':		function('s:on_select'),
			\ 'filter':			function('s:popup_filter')
			\ }

	const winid = popup_menu(output, opts)
endfunction
endif

" --------------------------------------------------------------
" add_item
" --------------------------------------------------------------
function! oldfiles#add_item(acmd_bufnr) abort
	" Get the full path to the filename
	let fname = fnamemodify(bufname(a:acmd_bufnr + 0), ':p')

	" 以下に該当する場合は履歴に追加しない
	" 履歴ロック中、ファイル名が空、特殊バッファ、リードオンリー
	if g:lock_oldfiles || empty(fname) || !empty(&buftype) || !filereadable(fname)
		return
	endif

	" Load the latest oldfiles list
	let oldfiles = s:load_oldfiles()

	" Remove the new file name from the existing list (if already present)
	call filter(oldfiles, 'v:val !=# fname')

	" Add the new file list to the beginning of the updated old file list
	call insert(oldfiles, fname, 0)

	" 履歴の最大数に丸める
	let oldfiles = oldfiles[:50-1]

	" 履歴をセーブ
	call writefile(oldfiles, s:OL_FILE)
endfunction

" --------------------------------------------------------------
" OL
" --------------------------------------------------------------
function! oldfiles#oldfiles() abort
	" Quickfixウィンドウにはバッファをオープンさせないため、Quickfixから起動時はここで終了させる
	if &buftype == 'quickfix'
		call s;warn_msg("Cannot executed with quickfix window")
		return
	endif

	" 履歴を読み込む
	let s:OldFiles = s:load_oldfiles()
	if empty(s:OldFiles)
		call s:warn_msg('Old files list is empty')
		return
	endif

	call s:open_popup()
endfunction

" restore 'cpo'
let &cpo = s:cpo_save
unlet s:cpo_save

