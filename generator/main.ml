let () =
  let argc = Array.length Sys.argv in
  if argc < 3 then (
    Printf.eprintf "Usage: %s <config.lua> <output-dir>\n" Sys.argv.(0);
    exit 1);
  let lua_path = Sys.argv.(1) in
  let output_dir = Sys.argv.(2) in
  Generate.run lua_path output_dir
