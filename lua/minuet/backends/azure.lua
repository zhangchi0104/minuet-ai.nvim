local M = {}
local config = require('minuet').config
local utils = require 'minuet.utils'

local config = require('minuet').config
local common = require 'minuet.backends.common'
local utils = require 'minuet.utils'

local M = {}

M.is_available = function()
    local options = vim.deepcopy(config.provider_options.azure)
    if options.end_point == ''  or options.deployment == '' then
        return false
    end

    if vim.env.AZURE_OPENAI_API_KEY == nil or vim.env.AZURE_OPENAI_API_KEY == '' then
        return false
    else
        return true
    end
end

if not M.is_available() then
    utils.notify(
        'The provider specified as Azure is not properly configured.',
        'error',
        vim.log.levels.ERROR
    )
end

M.complete = function(context_before_cursor, context_after_cursor, callback)
    local options = vim.deepcopy(config.provider_options.azure)
    local data = {}
    data = vim.tbl_deep_extend('force', data, options.optional or {})

    local language = utils.add_language_comment()
    local tab = utils.add_tab_comment()
    context_before_cursor = language .. '\n' .. tab .. '\n' .. context_before_cursor
    local api_version = options.api_version or '2024-10-21'
    data.prompt = context_before_cursor
    data.suffix = context_after_cursor

    local data_file = utils.make_tmp_file(data)

    if data_file == nil then
        return
    end

    local items = {}
    local request_complete = 0
    local n_completions = config.n_completions
    local has_called_back = false

    local function check_and_callback()
        if request_complete >= n_completions and not has_called_back then
            has_called_back = true

            items = M.filter_context_sequences_in_items(items, context_after_cursor)

            items = utils.remove_spaces(items)

            callback(items)
        end
    end
    local request_url = options.end_point .. '/openai/deployments/' .. options.deployment .. '/chat/completions?' .. api_version
    for _ = 1, n_completions do
        local args = {
            '-L',
            request_url,
            '-H',
            'Content-Type: application/json',
            '-H',
            'Accept: application/json',
            '-H',
            'api-key: ' .. vim.env.AZURE_OPENAI_API_KEY,
            '--max-time',
            tostring(config.request_timeout),
            '-d',
            '@' .. data_file,
        }

        if config.proxy then
            table.insert(args, '--proxy')
            table.insert(args, config.proxy)
        end

        job:new({
            command = 'curl',
            args = args,
            on_exit = vim.schedule_wrap(function(response, exit_code)
                -- Increment the request_send counter
                request_complete = request_complete + 1

                local result

                if options.stream then
                    result = utils.stream_decode(response, exit_code, data_file, options.name, get_text_fn)
                else
                    result = utils.no_stream_decode(response, exit_code, data_file, options.name, get_text_fn)
                end

                if result then
                    table.insert(items, result)
                end

                check_and_callback()
            end),
        }):start()
    end

end

return M
