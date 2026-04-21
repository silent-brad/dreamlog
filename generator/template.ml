open Jingoo
open Jg_types
open Types

let day_of_week y m d =
  let t = [| 0; 3; 2; 5; 0; 3; 5; 1; 4; 6; 2; 4 |] in
  let y = if m < 3 then y - 1 else y in
  (y + (y / 4) - (y / 100) + (y / 400) + t.(m - 1) + d) mod 7

let month_abbr =
  [| ""; "Jan"; "Feb"; "Mar"; "Apr"; "May"; "Jun"; "Jul"; "Aug"; "Sep"; "Oct"; "Nov"; "Dec" |] [@ocamlformat "disable"]

let day_abbr = [| "Sun"; "Mon"; "Tue"; "Wed"; "Thu"; "Fri"; "Sat" |]

let rfc822_of_date date_str =
  match String.split_on_char '-' date_str with
  | [ y; m; d ] ->
      let yi = int_of_string y
      and mi = int_of_string m
      and di = int_of_string d in
      Printf.sprintf "%s, %02d %s %04d 00:00:00 +0000"
        day_abbr.(day_of_week yi mi di)
        di month_abbr.(mi) yi
  | _ -> date_str

let model_of_item item =
  Tobj
    [
      ("slug", Tstr item.slug);
      ("title", Tstr item.title);
      ("date", Tstr item.date);
      ("body", Tsafe item.html_fragment);
      ("languages", Tlist (List.map (fun l -> Tstr l) item.languages));
      ("title_escaped", Tsafe (Util.xml_escape item.title));
      ("rfc822_date", Tstr (rfc822_of_date item.date));
      ("body_cdata", Tsafe (Util.cdata_wrap item.html_fragment));
      ("url", Tstr item.url);
    ]

let site_model (config : site_config) =
  Tobj
    [
      ("name", Tstr config.name);
      ("subtitle", Tstr config.subtitle);
      ("base_url", Tstr config.base_url);
    ]

let expand_permalink permalink item_slug =
  let buf = Buffer.create (String.length permalink) in
  let len = String.length permalink in
  let rec go i =
    if i >= len then ()
    else if i + 5 <= len && String.sub permalink i 5 = ":slug" then (
      Buffer.add_string buf item_slug;
      go (i + 5))
    else (
      Buffer.add_char buf permalink.[i];
      go (i + 1))
  in
  go 0;
  Buffer.contents buf
