local config = require("leetcode.config")
local lc_utils = require("leetcode.utils")

local M = {}

local function notify(message, level)
    vim.notify(message, level or vim.log.levels.INFO, { title = "leetcode.nvim" })
end

local function current_code(question)
    if not (question and question.bufnr and vim.api.nvim_buf_is_valid(question.bufnr)) then
        return question and question:snippet(true) or ""
    end

    local range = question:editor_section_range("code")
    if range.complete then
        return table.concat(range.lines, "\n", range.start_i, range.end_i)
    end

    return question:snippet(true) or ""
end

local function question_description(question)
    local q = question.q or {}
    local content = type(q.content) == "string" and q.content or ""
    local translated = type(q.translated_content) == "string" and q.translated_content or ""
    return lc_utils.translate(content, translated)
end

local function question_tags(question)
    local tags = {}
    local topic_tags = type(question.q.topic_tags) == "table" and question.q.topic_tags or {}
    for _, tag in ipairs(topic_tags) do
        table.insert(tags, tag.name or tag.slug or "")
    end
    return vim.tbl_filter(function(tag)
        return tag ~= ""
    end, tags)
end

local function question_hints(question)
    local hints = type(question.q.hints) == "table" and question.q.hints or {}
    return vim.tbl_map(function(hint)
        return tostring(hint)
    end, hints)
end

function M.build_context(question)
    return {
        title = question.q.title or "",
        title_slug = question.q.title_slug or "",
        difficulty = question.q.difficulty or "",
        lang = question.lang or config.lang,
        description = question_description(question),
        tags = question_tags(question),
        hints = question_hints(question),
        code = current_code(question),
        testcase = question.console and question.console.testcase and question.console.testcase:content() or "",
    }
end

function M.render_context(context)
    local parts = {
        "# LeetCode Problem Context",
        "",
        ("- Title: %s"):format(context.title),
        ("- Title Slug: %s"):format(context.title_slug),
        ("- Difficulty: %s"):format(context.difficulty),
        ("- Language: %s"):format(context.lang),
    }

    if not vim.tbl_isempty(context.tags) then
        table.insert(parts, ("- Tags: %s"):format(table.concat(context.tags, ", ")))
    end

    table.insert(parts, "")
    table.insert(parts, "## Problem Description")
    table.insert(parts, context.description ~= "" and context.description or "(empty)")

    if not vim.tbl_isempty(context.hints) then
        table.insert(parts, "")
        table.insert(parts, "## Hints")
        for index, hint in ipairs(context.hints) do
            table.insert(parts, ("%d. %s"):format(index, hint))
        end
    end

    if context.testcase ~= "" then
        table.insert(parts, "")
        table.insert(parts, "## Active Testcase")
        table.insert(parts, "```text")
        table.insert(parts, context.testcase)
        table.insert(parts, "```")
    end

    table.insert(parts, "")
    table.insert(parts, "## Current Code")
    table.insert(parts, ("```%s"):format(context.lang))
    table.insert(parts, context.code ~= "" and context.code or "")
    table.insert(parts, "```")

    return table.concat(parts, "\n")
end

function M.open(opts)
    opts = opts or {}

    local question = lc_utils.curr_question()
    if not question then
        return
    end

    local ok, codecompanion = pcall(require, "codecompanion")
    if not ok then
        notify("CodeCompanion is not available", vim.log.levels.ERROR)
        return
    end

    local cc = config.user.companion or {}
    local prompt = opts.prompt or cc.default_prompt or ""
    local params = {
        adapter = cc.adapter,
    }

    if cc.model and cc.model ~= "" then
        params.model = cc.model
    end

    local context = M.build_context(question)
    return codecompanion.chat({
        auto_submit = cc.auto_submit ~= false,
        ignore_system_prompt = true,
        params = params,
        title = ("LeetCode: %s"):format(context.title ~= "" and context.title or context.title_slug),
        user_prompt = prompt,
        window_opts = cc.window,
        callbacks = {
            on_created = function(chat)
                chat:add_context(
                    {
                        role = "user",
                        content = M.render_context(context),
                    },
                    "leetcode",
                    ("<leetcode:%s>"):format(context.title_slug ~= "" and context.title_slug or chat.id),
                    {
                        visible = false,
                        tag = "leetcode_context",
                    }
                )
            end,
        },
    })
end

function M.prompt_and_open()
    local cc = config.user.companion or {}
    local default_prompt = cc.default_prompt or ""

    if cc.prompt_user == false then
        return M.open({ prompt = default_prompt })
    end

    vim.ui.input({
        prompt = "What do you want help with? ",
        default = default_prompt,
    }, function(input)
        if input == nil then
            return
        end

        local prompt = vim.trim(input)
        if prompt == "" then
            prompt = default_prompt
        end

        M.open({ prompt = prompt })
    end)
end

return M
