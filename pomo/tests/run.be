# Runs every tests/test_*.be under the reference Berry interpreter. Run from the pomo/ directory.
import os
import global
import string
compile("tests/harness.be", "file")()
var files = []
for f : os.listdir("tests")
  if string.find(f, "test_") == 0 && string.find(f, ".be") > 0 files.push(f) end
end
for f : files
  compile("tests/" + f, "file")()
end
var passed = 0
var failed = 0
for tc : global.tests
  try
    tc[1]()
    passed += 1
    print("PASS " + tc[0])
  except .. as e, m
    failed += 1
    print("FAIL " + tc[0] + ": " + str(e) + " " + str(m))
  end
end
print(format("%d passed, %d failed", passed, failed))
if failed > 0 os.exit(1) end
