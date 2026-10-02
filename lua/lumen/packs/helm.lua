---@type lumen.Pack
return {
  desc = "Helm charts (helm-ls)",
  ft = { "helm" },
  parsers = { "helm", "yaml" },
  servers = { helm_ls = {} },
  -- templates inside a chart (a dir with Chart.yaml above it) are helm, not plain yaml
  setup = function()
    local function helm(path)
      return vim.fs.root(path, "Chart.yaml") and "helm" or nil
    end
    vim.filetype.add({
      pattern = {
        [".*/templates/.*%.ya?ml"] = helm,
        [".*/templates/.*%.tpl"] = helm,
        ["helmfile.*%.ya?ml"] = "helm",
      },
    })
  end,
}
