" ------------------------------------------------------------------------------
" File:		plugin/agtd.vim - Almighty GTD File
"
" Author:	    Francisco Garcia Rodriguez <contact@francisco-garcia.net>
"
" Licence:	
"
" Almighty GTD File Vim Script
"
" Copyright (C) 2010  Francisco Garcia Rodriguez <contact@francisco-garcia.net>
" 
" This program is free software: you can redistribute it and/or modify
" it under the terms of the GNU General Public License as published by
" the Free Software Foundation, either version 3 of the License, or
" (at your option) any later version.
" 
" This program is distributed in the hope that it will be useful,
" but WITHOUT ANY WARRANTY; without even the implied warranty of
" MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
" GNU General Public License for more details.
" 
" You should have received a copy of the GNU General Public License
" along with this program.  If not, see <http://www.gnu.org/licenses/>.
" 
" Version:	0.3 (Alpha)
"
" Files:	
"		doc/agtd.vim
"		plugin/agtd.vim
"		syntax/agtd.vim
"		ftplugin/agtd.vim
"
" History:
"   0.3  License text fix
"        New author email address
"        New folding function. Now based on sections, not on indentation
"        UTL configuration removed
"
"   0.2  Bug fixing and clutter clean-up
"        Calendar displays colors
"        Variable naming matches better plug-in name
"        Task insertions works when there is an http:// address
"        Common environment values pushed into a ftplugin
"        UTL Schema prototype for ssh links
"
"   0.1  Initial version
" ------------------------------------------------------------------------------

if exists("loaded_agtd") 
    finish
endif
let loaded_agtd = "0.3"

let s:agtd_dateRegx    = '\u::\d\d-\d\d\(-\d\d\)\?'
let s:agtd_ProjectRegx = '^\s\+\u\+'


" Move task at TOP
"
" Get current task line (usually within a PROJECT section) and move it to the
" top of the buffer, where the current todo tasks should be. It will also try
" to append a project label. As an example, when the cursor is on this line:
"
"       @net Find person
"
" It will be moved to the 2nd line of the buffer as:
" (1st should be the section title)
"
"       @net p:task:subtask Find person
"
function! Gtd_insertTask()
    let task_line_no = line ('.')
    let line         = getline (task_line_no)
    let task         = matchstr (line,' \w.*$')
    let context      = matchstr (line,'@\w\+')
    if context == ""
        let v:errmsg = "Line has not a context label ..@.."
        echohl ErrorMsg | echo v:errmsg | echohl None
        return
    endif

    " Get project label as in p:pro:sub1:sub2
    if match (line,' p:\w*') == -1
        " Line has no label 
        let lastCol = 0
        let project = ""
        let col = 0
        while col != 4
            " Last project name is in column 4

            " Get project name looking backwards
            let pos = search(s:agtd_ProjectRegx, 'b', 1)
            if pos == 0
                let v:errmsg = "Could not build project name"
                echohl ErrorMsg | echo v:errmsg | echohl None
                return
            endif

            " Project name found: go to get line and colum
            call cursor (pos)
            let line = getline (pos)
            let col = match(line,'\u\+')

            if col != lastCol 
                " Project names in the same column are siblings, not an ancestor
                let project = ":" . tolower(matchstr(line,'\u\+')) . project
                let lastCol = col
            endif
        endwhile
        let entry = "    ".context." p".project.task
    else
        let entry = "    ".context." ".task
    endif

    " Insert new project line
    call append(1, entry)
    call cursor (task_line_no + 1,0)
    normal dd
    echo "New task added: " . entry
endfunction


" Go to PROJECT line
"
" Parse the current line to find a p:project label and decompose it to find
" the rest of the tasks related with such project. 
"
" If there are different subprojects (p:xxx:yy:z) the function will actually
" start jumping step by step, deeper into the hierarchy until the end or the
" first failed search
function! Gtd_getProject()
    let line = getline ('.')
    let label = matchstr(line, 'p:\S\+')
    let path = split (label, ':')

    " Find project first line
    for i in path[1:]
        let project = toupper(i)
        call cursor ( search('^\s\+'.project) )
        normal zo
    endfor
    let projectPos = getpos ('.')

    " Get tasks for same project (TODO later)
    "echo "Tasks for project ".label
    normal gg
    let pos = search(label, 'W')
    let listLines = []
    while pos != 0
        let line = getline ('.')
        call add (listLines, line)
        let pos = search(label, 'W')
    endwhile

    " Return to project first line
    call setpos ('.', projectPos)
    normal zt
    normal jzo
    " echo listLines
endfunction

" Get the column of the first character for sections for the line 'lineNum'
" 
" Sections start with a section marker (# @ ;) or just contain a project title
" (uppercase and '_'). 
"
" If either of them is found, it returns the column of the
" first character. Otherwise returns -1
"
function! Gtd_getSectionColumn(lineNum)
    let lineText = getline (a:lineNum)
    let lineCol = match (lineText,'\S')
    if lineCol == -1
        " No fold level for empty line
        return -1
    endif

    " Check for lines with just a project title
    let projectTitle = match (lineText,'^\s\+[\u_]\+\s*')
    if projectTitle == 0
        return lineCol
    endif

    let markerPos = match (lineText,'[#@;]')
    if markerPos == lineCol
        " Line starting with a section marker
        return markerPos
    else
        " Other type of lines
        return -1
    endif
endfu


" FoldLevel for AGTD files
"
" The fold level is based on the column of the first section marker divided
" by the current tab width. Tab markers are identified by the function
" Gtd_getSectionColumn()
"
" If no section marker is found in the current line, it will look for one in
" the previous lines divided. In such cases it will be assumed that the
" current line is one level deeper (+1) within the first previous section
" line.
"
function! Gtd_foldLevel(pos)
    " Get section marker position
    let sectionColumn = -1
    let lineNum = a:pos + 1
    while sectionColumn == -1 && lineNum != 1
        let lineNum -= 1
        let sectionColumn = Gtd_getSectionColumn(lineNum)
    endwhile

    if sectionColumn == -1
        " No section found
        return 0
    endif

    let level = sectionColumn / &shiftwidth
    if lineNum != a:pos
        " Section had to be searched in previous lines. Therefore Current line
        " is contained within a section: The fold level is +1 greater than its
        " section
        let level += 1
    endif
    return level
endfu


" Search the file for mark tags and set them
"
" Starting from the beggining of the file, search for auto-mark labels and set
" them as a new mark
function! Gtd_setMarks()
    call cursor (1)
    let pos = search('m::\l', 'W')
    while pos != 0
        let line = getline ('.')
        let mark = matchstr (line, 'm::\l')
        let mark = strpart (mark, 3, 1)
        exe "mark " mark

        let pos = search('m::\l', 'W')
    endwhile
    normal gg
endfunction


" Search project
"
" Locate first appearence of project name, jump to it and unfold
function! Gtd_searchProject(pro)
    let line_no = search ('^\s\+'.a:pro) 
    call cursor (line_no) 
    exe line_no."foldopen"
    exe line_no."foldopen"
    exe line_no."foldopen"
    exe line_no."foldopen"
    normal ztl
    exe line_no+1."foldopen"
endfunction


" List of projects 
"
" Custom function for auto-completion. Auto-complete with project names within
" current buffer.
function! Gtd_getProjectList(ArgLead, CmdLine, CursorPos)
    let proList = []
    let proName = '^\s\+'.a:ArgLead.'\u\+'
    let startPos = getpos ('.')
    call cursor (1,1)
    let pos = search(proName) 
    while pos != 0
        call cursor (pos)
        let line = getline (pos)
        let pro = matchstr (line,'\u\+')
        echo pro
        if index(proList, pro) == -1
            call add(proList, pro)
        endif

        let pos = search(proName, 'W') 
    endwhile
    call setpos ('.', startPos)
    return proList
endfunction


" Collect lines with a date mark on it
function! s:Gtd_getDateLines()
    let startPos = getpos ('.')
    let datesList = []
    call cursor (1,1)

    " Search tasks with dates
    let pos = search(s:agtd_dateRegx) 
    while pos != 0
        call cursor (pos)
        let line = getline ('.')
        let date = matchstr (line,s:agtd_dateRegx)
        let date = strpart (date, 3)
        if strlen (date) == 5
            let date = strftime("%Y")."-".date
        endif

        " Remove indentation
        let line = substitute (line, '^\s\+', "", "")
        let line = date."    ".line
        call add (datesList, line)
        let pos = search(s:agtd_dateRegx, 'W') 
    endwhile
    call setpos ('.', startPos)
    return datesList
endfunction


" Create a buffer with all marked the marked events
function! Gtd_displayCalendar()
    let datesList = s:Gtd_getDateLines()

    " Make that temporal buffer
    let tmpBuffer = "tmpGtdCalendarDisp.tmp"
    let gtdBuffer = bufnr ('')
    silent! exe 'edit '. tmpBuffer
    set buftype=nofile
    set bufhidden=hide
    set noswf
    set nobuflisted
    set filetype=agtd
    set fdm=indent
    set foldminlines=0

    " Display sorted list of dates and grouped by months
    let thisMonth = "XX"
    for line in sort (datesList)
        " Remove date and following empty spaces
        let line = substitute (line, s:agtd_dateRegx.'\s*', "", "")

        " Insert month if different from the previous one
        let month = matchstr(line, '-\d\d-')
        if match (month, thisMonth) == -1
            let thisMonth = month
            call append ('$', "")
            call append ('$', month)
        endif

        call append ('$', "\t".line)
    endfor

    " Remove two empty lines from the beginning and open all folds
    normal gg2ddzR
    set ro
endfunction


" Build an iCalendar file 
"
" Search in the current buffer all timestamps and build an iCalendarfile
" according RFC-5545. All the comments will be plain events, since the current
" notation will not recognize time-frames.
" 
" NOTES:
"   * The generated UID is random. If you generate and import the output
"   several times, you will get the same event repeated in your calendar
"   program because it cannot identify updated components TODO
function! Gtd_buildICalFile()
    let datesList = s:Gtd_getDateLines()
    let uid = 0

    " File header
    echo "BEGIN:VCALENDAR"
    echo "PRODID:-//DIGITAL-LUMBERJACK/AGTD Vim Calendar File 0.1//EN"
    echo "VERSION:2.0"
    
    for line in sort (datesList)
        let stamp = substitute(line, "-", "", "g")
        let stamp = matchstr(line, "\d\{8}")
        let summary = strpart (line, 13)
        echo "BEGIN:VEVENT"
        echo "DTSTAMP:".stamp."T000000Z"
        echo "UID:".uid."@agtd-vim"
        echo "SUMMARY:".summary

        let uid = uid + 1
    endfor
    echo "END:VCALENDAR"
endfunction

" Almighty GTD Vim script commands
command -nargs=1 -complete=customlist,Gtd_getProjectList GSearch call Gtd_searchProject("<args>")
command GCalendar call Gtd_displayCalendar()
command GInsert call Gtd_insertTask()
command GGo call Gtd_getProject() 
"command Gsort .sort /\s\{8}/

finish

