local config = require("leetcode.config")

local Group = require("leetcode-ui.group")
local Line = require("leetcode-ui.line")
local Padding = require("leetcode-ui.lines.padding")
local Split = require("leetcode-ui.split")

---@class lc.ui.Submissions : lc-ui.Split
---@field question lc.ui.Question
---@field state "loading"|"ready"|"empty"|"error"
---@field submissions table[]
---@field message? string
local Submissions = Split:extend("LeetSubmissions")

local function debug_log(msg)
    vim.schedule(function()
        vim.fn.histadd("message", "[submissions_panel] " .. msg)
    end)
end

local function status_hl(status)
    if status == "Accepted" then
        return "leetcode_easy"
    end

    if status == "Wrong Answer" or status == "Runtime Error" or status == "Time Limit Exceeded" then
        return "leetcode_hard"
    end

    return "leetcode_normal"
end

local function status_icon(status)
    if status == "Accepted" then
        return config.icons.status.ac, "leetcode_easy"
    end

    return config.icons.status.notac, "leetcode_hard"
end

local function trim_timestamp(timestamp)
    if not timestamp or timestamp == "" then
        return "unknown"
    end

    return timestamp:gsub(" %u+$", "")
end

function Submissions:populate()
    local layout = Group({}, {
        padding = {
            left = 1,
            right = 1,
            top = 1,
        },
    })

    local header = Line()
    header:append("Past Submissions", "leetcode_medium")
    layout:insert(header)
    layout:insert(Padding(1))

    if self.state == "loading" then
        local line = Line()
        line:append("Loading submissions...", "leetcode_alt")
        layout:insert(line)
    elseif self.state == "error" then
        local line = Line()
        line:append(self.message or "Submission service unavailable", "leetcode_hard")
        layout:insert(line)
    elseif self.state == "empty" then
        local line = Line()
        line:append("No past submissions yet", "leetcode_alt")
        layout:insert(line)
    else
        for index, submission in ipairs(self.submissions) do
            local title = Line()
            title:append(("%d. "):format(index), "leetcode_list")
            title:append(trim_timestamp(submission.submitted_at_pst), "leetcode_alt")
            layout:insert(title)

            local details = Line()
            local icon, icon_hl = status_icon(submission.submit_result)
            details:append(icon, icon_hl)
            details:append("  time=", "leetcode_list")

            local time_spent = submission.time_spent_minutes
            if time_spent == nil or time_spent == vim.NIL then
                details:append("n/a", "leetcode_alt")
            else
                details:append(("%sm"):format(time_spent), "leetcode_normal")
            end

            details:append("  test=", "leetcode_list")
            details:append(submission.is_test and "yes" or "no", submission.is_test and "leetcode_medium" or "leetcode_normal")
            details:append("  ", "leetcode_list")
            details:append(submission.submit_result or "Unknown", status_hl(submission.submit_result))
            layout:insert(details)

            if index < #self.submissions then
                layout:insert(Padding(1))
            end
        end
    end

    self.renderer:replace({ layout })
end

function Submissions:draw()
    self:populate()
    Submissions.super.draw(self)
end

function Submissions:set_loading()
    debug_log("set_loading")
    self.state = "loading"
    self.message = nil
    self.submissions = {}
    self:draw()
end

---@param msg string
function Submissions:set_error(msg)
    debug_log("set_error " .. tostring(msg))
    self.state = "error"
    self.message = msg
    self.submissions = {}
    self:draw()
end

---@param submissions table[]
function Submissions:update_submissions(submissions)
    debug_log("update_submissions count=" .. tostring(submissions and #submissions or 0))
    self.submissions = submissions or {}
    self.message = nil
    self.state = vim.tbl_isempty(self.submissions) and "empty" or "ready"
    self:draw()
end

function Submissions:fetch()
    debug_log("fetch begin for " .. self.question.q.title_slug)
    self:set_loading()

    local ok, saver = pcall(require, "submission_db_saver")
    if not ok then
        self:set_error("submission_db_saver.lua not found")
        return
    end

    saver.get_past_submissions(self.question, function(response)
        vim.schedule(function()
            if not self._.mounted then
                debug_log("callback ignored because panel unmounted")
                return
            end

            debug_log("callback response=" .. vim.inspect(response))
            if response.error then
                self:set_error(response.error)
                return
            end

            local submissions = response.submissions or {}
            self.question.past_submissions = submissions
            self:update_submissions(submissions)
        end)
    end, config.user.description.submissions.limit)
end

function Submissions:mount()
    Submissions.super.mount(self)
    self:fetch()

    local ui_utils = require("leetcode-ui.utils")
    ui_utils.buf_set_opts(self.bufnr, {
        modifiable = false,
        buflisted = false,
        swapfile = false,
        buftype = "nofile",
        filetype = config.name,
    })
    ui_utils.win_set_opts(self.winid, {
        winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder",
        wrap = false,
        colorcolumn = "",
        foldcolumn = "0",
        cursorcolumn = false,
        cursorline = false,
        number = false,
        relativenumber = false,
        list = false,
        spell = false,
        signcolumn = "no",
        linebreak = false,
    })
    ui_utils.win_set_winfixbuf(self.winid)

    self:draw()
    return self
end

---@param parent lc.ui.Question
function Submissions:init(parent)
    Submissions.super.init(self, {
        relative = {
            type = "win",
            winid = parent.description.winid,
        },
        position = "bottom",
        size = config.user.description.submissions.height,
        enter = false,
        focusable = true,
    })

    self.question = parent
    self.state = "loading"
    self.submissions = parent.past_submissions or {}
end

---@type fun(parent: lc.ui.Question): lc.ui.Submissions
local LeetSubmissions = Submissions

return LeetSubmissions
