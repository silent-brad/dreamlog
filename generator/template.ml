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

let ordinal_suffix d =
  match d mod 10 with
  | 1 when d <> 11 -> "st"
  | 2 when d <> 12 -> "nd"
  | 3 when d <> 13 -> "rd"
  | _ -> "th"

let format_date date_str =
  match String.split_on_char '-' date_str with
  | [ y; m; d ] ->
      let mi = int_of_string m and di = int_of_string d in
      Printf.sprintf "%s %d%s, %s" month_abbr.(mi) di (ordinal_suffix di) y
  | _ -> date_str

let rec lua_value_to_tvalue = function
  | VStr s -> Tstr s
  | VNum n -> if Float.is_integer n then Tint (int_of_float n) else Tfloat n
  | VBool b -> Tbool b
  | VList vs -> Tlist (List.map lua_value_to_tvalue vs)
  | VObj entries ->
      Tobj (List.map (fun (k, v) -> (k, lua_value_to_tvalue v)) entries)

let model_of_item ?(tag_url = fun _ -> "") item =
  Tobj
    [
      ("slug", Tstr item.slug);
      ("title", Tstr item.title);
      ("date", Tstr item.date);
      ("date_formatted", Tstr (format_date item.date));
      ("body", Tsafe item.html_fragment);
      ("languages", Tlist (List.map (fun l -> Tstr l) item.languages));
      ( "tags",
        Tlist
          (List.map
             (fun t -> Tobj [ ("name", Tstr t); ("url", Tstr (tag_url t)) ])
             item.tags) );
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

let expand_tag_permalink permalink tag =
  let buf = Buffer.create (String.length permalink) in
  let len = String.length permalink in
  let tag_ph = ":tag" in
  let tag_len = String.length tag_ph in
  let rec go i =
    if i >= len then ()
    else if i + tag_len <= len && String.sub permalink i tag_len = tag_ph then (
      Buffer.add_string buf tag;
      go (i + tag_len))
    else (
      Buffer.add_char buf permalink.[i];
      go (i + 1))
  in
  go 0;
  Buffer.contents buf
