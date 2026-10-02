---@type lumen.Pack
return {
  desc = "Terraform / HCL (terraform-ls, tflint)",
  ft = { "terraform", "terraform-vars", "hcl" },
  parsers = { "terraform", "hcl" },
  servers = { terraformls = {}, tflint = {} },
  formatters = { terraform = { "terraform_fmt" }, ["terraform-vars"] = { "terraform_fmt" }, hcl = { "terraform_fmt" } },
}
