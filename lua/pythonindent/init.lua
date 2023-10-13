-- PEP8 compatible Python indent file
-- Language:         Python
-- Maintainer:       Daniel Hahler <https://daniel.hahler.de/>
-- Prev Maintainer:  Hynek Schlawack <hs@ox.cx>
-- Prev Maintainer:  Eric Mc Sween <em@tomcom.de> (address invalid)
-- Original Author:  David Bustos <bustos@caltech.edu> (address invalid)
-- License:          CC0
--
-- vim-python-pep8-indent - A nicer Python indentation style for Vim.
-- Written in 2004 by David Bustos <bustos@caltech.edu>
-- Maintained from 2004-2005 by Eric Mc Sween <em@tomcom.de>
-- Maintained from 2013 by Hynek Schlawack <hs@ox.cx>
-- Maintained from 2017 by Daniel Hahler <https://daniel.hahler.de/>
--
-- To the extent possible under law, the author(s) have dedicated all copyright
-- and related and neighboring rights to this software to the public domain
-- worldwide. This software is distributed without any warranty.
-- You should have received a copy of the CC0 Public Domain Dedication along
-- with this software. If not, see
-- <http://creativecommons.org/publicdomain/zero/1.0/>.

-- Only load this indent file when no other was loaded.
if vim.b.did_indent then
    return
end
vim.b.did_indent = 1

vim.bo.lisp = false
vim.bo.autoindent = true
vim.bo.indentexpr = "GetPythonPEPIndent(v:lnum)"
vim.bo.indentkeys = "!^F,o,O,<:>,0),0],0},=elif,=except"

-- Check if these global variables are not defined, then set default values.
if vim.g.python_pep8_indent_multiline_string == nil then
    vim.g.python_pep8_indent_multiline_string = 0
end

if vim.g.python_pep8_indent_hang_closing == nil then
    vim.g.python_pep8_indent_hang_closing = 0
end

if vim.g.python_pep8_indent_searchpair_timeout == nil then
    -- Determine the timeout value based on Vim version.
    if vim.fn.has('patch-8.0.1483') then
        vim.g.python_pep8_indent_searchpair_timeout = 150
    else
        vim.g.python_pep8_indent_searchpair_timeout = 0
    end
end

-- Define block rules for various Python control structures.
local block_rules = {
    ['^\\s*elif\\>'] = {{'if', 'elif'}, {'else'}},
    ['^\\s*except\\>'] = {{'try', 'except'}, {}},
    ['^\\s*finally\\>'] = {{'try', 'except', 'else'}, {}}
}

local block_rules_multiple = {
    ['^\\s*else\\>'] = {{'if', 'elif', 'for', 'try', 'except'}, {}}
}

-- Define the pairs of parentheses for searching.
local paren_pairs = {'()', '[]', '{}'}

-- Function to find the position of the opening parenthesis.
local function find_opening_paren(lnum, col)
    -- Skip comments when searching for parentheses.
    if vim.fn.synIDattr(vim.fn.synID(lnum, col, 0), 'name') == 'comment' then
        return {0, 0}
    end

    vim.fn.cursor(lnum, col)
    local nearest = {0, 0}
    local timeout = vim.g.python_pep8_indent_searchpair_timeout
    local skip_special_chars = 'v:lua._skip_special_chars(vim.fn.line("."), vim.fn.col("."))'
    for _, pair in ipairs(paren_pairs) do
        local stopline = math.max(0, vim.fn.line('.') - pair[2], nearest[1])
        local next_pos = vim.fn.searchpairpos(pair[1], '', pair[2], 'bnW', skip_special_chars, stopline, timeout)
        if next_pos[1] > 0 and (next_pos[1] > nearest[1] or (next_pos[1] == nearest[1] and next_pos[2] > nearest[2])) then
            nearest = next_pos
        end
    end
    return nearest
end

-- Function to find the start of a multiline statement.
local function find_start_of_multiline_statement(lnum)
    local start = lnum
    while start > 1 do
        if vim.fn.matchstr(vim.fn.getline(start - 1), '\\\\$') ~= '' then
            start = vim.fn.prevnonblank(start - 1)
        else
            local paren_pos = find_opening_paren(start, 1)
            if paren_pos[1] <= 0 then
                return start
            else
                start = paren_pos[1]
            end
        end
    end
    return start
end

-- Function to find the start of a code block.
local function find_start_of_block(lnum, types, skip, multiple)
    local result = {}
    local re = [[\v\^\s*\(%s\)\>]]:format(table.concat(types, '|'))
    local re_skip = ''
    if #skip > 0 then
        re_skip = [[\v\^\s*\(%s\)\>]]:format(table.concat(skip, '|'))
    end
    local last_indent = vim.fn.indent(lnum) + 1
    local line = vim.fn.getline(lnum)
    local line_num = lnum - 1
    while line_num > 0 and last_indent > 0 do
        local indent = vim.fn.indent(line_num)
        if indent < last_indent then
            local current_line = vim.fn.getline(line_num)
            if not re_skip:match(current_line) and re:match(current_line) then
                if not multiple then
                    return {indent}
                end
                if vim.fn.index(result, indent) == -1 then
                    table.insert(result, indent)
                end
                last_indent = indent
            end
        end
        line_num = vim.fn.prevnonblank(line_num - 1)
    end
    return result
end

-- Function to match an expression on a line.
local function match_expr_on_line(expr, lnum, start, ...)
    local text = vim.fn.getline(lnum)
    local args = { ... }
    local ending = args[1] or #text
    if start > ending then
        return 1
    end
    local r = 1
    for i = start, ending do
        vim.fn.cursor(lnum, i)
        if not (vim.fn.eval(expr) or text:sub(i, i):match('%s')) then
            r = 0
            break
        end
    end
    return r
end

-- Function to handle Python indentation like an opening parenthesis.
local function indent_like_opening_paren(lnum)
    local paren_pos = find_opening_paren(lnum, 1)
    if paren_pos[1] <= 0 then
        return -2
    end
    local line = vim.fn.getline(paren_pos[1])
    local base = vim.fn.indent(paren_pos[1])

    local nothing_after_opening_paren = match_expr_on_line('_skip_after_opening_paren()', paren_pos[1], paren_pos[2] + 1)
    local starts_with_closing_paren = vim.fn.getline(lnum):match('^%s*[})]')

    local hang_closing = vim.fn.get(vim.b, 'python_pep8_indent_hang_closing', vim.g.python_pep8_indent_hang_closing) or 0

    if nothing_after_opening_paren then
        if starts_with_closing_paren and not hang_closing then
            return base
        else
            return base + vim.fn.shiftwidth()
        end
    else
        return paren_pos[2]
    end
end

-- Function to handle Python indentation like a code block.
local function indent_like_block(lnum)
    local text = vim.fn.getline(lnum)
    for _, block_info in ipairs({{0, block_rules}, {1, block_rules_multiple}}) do
        local multiple = block_info[1]
        local block_rules = block_info[2]
        for line_re, blocks_ignore in pairs(block_rules) do
            if not text:match(line_re) then
                goto continue
            end
            local blocks = blocks_ignore[1]
            local skip = blocks_ignore[2]
            local indents = find_start_of_block(lnum, blocks, skip, multiple)
            if #indents == 0 then
                return -1
            end
            if #indents == 1 then
                return indents[1]
            end
            local indent = vim.fn.indent(lnum)
            if vim.fn.index(indents, indent) ~= -1 then
                return indent
            end
            return indents[1]
        end
        ::continue::
    end
    return -2
end

-- Function to handle Python indentation like the previous line.
local function indent_like_previous_line(lnum)
    local line_num = vim.fn.prevnonblank(lnum - 1)
    if line_num < 1 then
        return -1
    end
    local line = vim.fn.getline(line_num)
    local start = find_start_of_multiline_statement(line_num)
    local base = vim.fn.indent(start)
    local current = vim.fn.indent(lnum)
    local lastcol = #line
    local col = lastcol
    while true do
        if col == 1 then
            break
        end
        if line:sub(col, col):match('%s') or vim.fn.eval('_skip_special_chars(line_num, col)') then
            col = col - 1
            goto continue
        elseif line:sub(col, col) == ':' then
            return base + vim.fn.shiftwidth()
        end
        break
        ::continue::
    end
    if line:match('\\$') and not vim.fn.eval('s:_skip_special_chars(lnum, lastcol)') then
        if line:match(b:control_statement) then
            local paren_info = find_opening_paren(line_num, 1)
            if paren_info[1] <= 0 then
                return base + vim.fn.shiftwidth() * 2
            end
        end
        return base + vim.fn.shiftwidth()
    end
    local empty = vim.fn.getline(lnum):match('^%s*$')
    if empty and line_num > 1 and (vim.fn.getline(line_num - 1):match('^%s*$') and not vim.fn.getline(lnum + 1):match('^%s*$')) then
        return vim.fn.indent(lnum + 1)
    end
    if line:match(s:stop_statement) then
        if empty or current > base - vim.fn.shiftwidth() then
            return base - vim.fn.shiftwidth()
        end
        return -1
    end
    if (current or not empty) and vim.fn.eval('s:is_dedented_already(current, base)') then
        return -1
    end
    return base
end

-- Function to check if the code is already dedented.
local function is_dedented_already(current, base)
    local dedent_size = current - base
    return (dedent_size < 0 and current % vim.fn.shiftwidth() == 0) and 1 or 0
end

-- Function to check if a line is part of a Python string.
local function is_python_string(lnum, ...)
    local line = vim.fn.getline(lnum)
    local cols = type(arg[1]) == 'table' and arg[1] or { ... }
    for _, cnum in ipairs(cols) do
        local syntax_ids = vim.fn.synstack(lnum, cnum)
        local is_string = true
        for _, syn_id in pairs(syntax_ids) do
            if not vim.fn.synIDattr(syn_id, 'name'):match('python%S*String') then
                is_string = false
                break
            end
        end
        if not is_string then
            return 0
        end
    end
    return 1
end

-- Main function to determine Python indentation.
function GetPythonPEPIndent(lnum)
    if lnum == 1 then
        return 0
    end

    local line = vim.fn.getline(lnum)
    local prevline = vim.fn.getline(lnum - 1)

    if is_python_string(lnum - 1, math.max(1, #prevline)) and (is_python_string(lnum, 1) or line:match('^%("""\|''''''\)') ~= nil) then
        local match_quotes = line:match('^%s*%(%(""\'\'\'\'\'\'\'\'\'%)"\'\'\'\'\'\'\'\'\'\)')
        if match_quotes then
            local quotes = line:sub(match_quotes, match_quotes + 2)
            local pairpos = vim.fn.searchpairpos(quotes, '', quotes, 'bW', '', 0, vim.g.python_pep8_indent_searchpair_timeout)
            if pairpos[1] ~= 0 then
                return vim.fn.indent(pairpos[1])
            else
                return -1
            end
        end

        if is_python_string(lnum - 1) then
            return -1
        end

        if prevline:match('^%("""\|\'\'\'\'\'\'\'\'\'%\)') ~= nil then
            return vim.fn.indent(lnum - 1)
        end

        local indent_multi = vim.fn.get(vim.b, 'python_pep8_indent_multiline_string', vim.g.python_pep8_indent_multiline_string) or 0
        if prevline:match([[\%("""|'''''')$]]) ~= nil then
            if (vim.bo.autoindent and vim.fn.indent(lnum) == vim.fn.indent(lnum - 1)) or line:match('^%s+$') ~= nil then
                if indent_multi == -2 then
                    return vim.fn.indent(lnum - 1) + vim.fn.shiftwidth()
                end
                return indent_multi
            end
        end

        if line:match('^%s*%S') ~= nil then
            return -1
        end

        if indent_multi ~= -2 then
            return indent_multi
        end

        return indent_like_opening_paren(lnum)
    end

    local indent = indent_like_opening_paren(lnum)
    if indent >= -1 then
        return indent
    end

    indent = indent_like_block(lnum)
    if indent >= -1 then
        return indent
    end

    return indent_like_previous_line(lnum)
end
