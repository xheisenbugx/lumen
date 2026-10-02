---@type lumen.Pack
return {
  desc = "Markdown (marksman, in-buffer rendering)",
  ft = { "markdown" },
  parsers = { "markdown", "markdown_inline", "html", "latex", "yaml" },
  servers = { marksman = {} },
  plugins = {
    {
      "MeanderingProgrammer/render-markdown.nvim",
      ft = { "markdown" },
      opts = {
        -- render in every mode (not only Normal); just the line you're editing shows raw markdown
        render_modes = true,
        anti_conceal = { enabled = true, above = 0, below = 0 },
        code = { sign = false, width = "block", right_pad = 1 },
        heading = { sign = false, icons = { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " } },
        checkbox = { enabled = true },
        completions = { blink = { enabled = true } },
      },
      config = function(_, opts)
        require("render-markdown").setup(opts)
        Snacks.toggle({
          name = "Render markdown",
          get = function()
            return require("render-markdown").get()
          end,
          set = function(on)
            require("render-markdown")[on and "enable" or "disable"]()
          end,
        }):map("<leader>um")
      end,
    },
  },
}
