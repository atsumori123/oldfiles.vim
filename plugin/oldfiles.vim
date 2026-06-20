if exists('loaded_oldfiles')
	finish
endif
let loaded_oldfiles = 1

autocmd BufRead			* call oldfiles#add_item(expand('<abuf>'))
autocmd BufNewFile		* call oldfiles#add_item(expand('<abuf>'))
autocmd BufWritePost	* call oldfiles#add_item(expand('<abuf>'))
autocmd QuickFixCmdPre	*vimgrep* let g:lock_oldfiles = 1
autocmd QuickFixCmdPost	*vimgrep* let g:lock_oldfiles = 0

command! -nargs=? OL call oldfiles#oldfiles()

