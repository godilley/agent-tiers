# Display labels and colours only; not evidence of runtime model selection.
def statusModelColor:
  ascii_downcase |
  if test("haiku") then "32"
  elif test("sonnet") then "36"
  elif test("opus") then "35"
  elif test("fable") then "33"
  else "2" end;
def statusModelDisplay: .;
