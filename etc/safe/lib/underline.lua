-- underline.lua — keep the form's blanks visible in the PDF.
--
-- MEASURED 2026-09-04 with pandoc 2.9.2.1: the LaTeX writer DROPS raw HTML, so
-- `Address:<u>  </u>` renders as `Address:` with no rule to write on, and the underlined
-- defined terms ("Equity Financing", "excluding") lose their underline. Every blank in
-- every YC form is a `<u>…</u>`, so without this filter the generated PDF silently loses
-- the whole fill-in surface — the .md is right and the PDF is not.
--
-- pandoc gained a first-class Underline element in 2.10; this filter is what a 2.9
-- toolchain needs, and it is harmless on later ones (they parse `<u>` to Underline and
-- never produce the RawInline pair this matches).
--
-- A blank (whitespace-only content) becomes a rule whose width tracks the number of
-- spaces the form used, so a six-space signature blank stays wider than a one-space one.

local function isU(el, close)
  return el.t == "RawInline"
    and el.format == "html"
    and el.text:lower():gsub("%s", "") == (close and "</u>" or "<u>")
end

function Inlines(ins)
  local out, buf = {}, nil
  for _, el in ipairs(ins) do
    if isU(el, false) then
      buf = {}
    elseif isU(el, true) and buf then
      local inner = pandoc.utils.stringify(buf)
      if inner:match("^%s*$") then
        local w = math.max(1.2, #inner * 0.6)
        table.insert(out, pandoc.RawInline("latex", string.format("\\underline{\\hspace{%.1fcm}}", w)))
      else
        table.insert(out, pandoc.RawInline("latex", "\\underline{"))
        for _, b in ipairs(buf) do table.insert(out, b) end
        table.insert(out, pandoc.RawInline("latex", "}"))
      end
      buf = nil
    elseif buf then
      table.insert(buf, el)
    else
      table.insert(out, el)
    end
  end
  if buf then for _, b in ipairs(buf) do table.insert(out, b) end end
  return out
end
