(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, *   INRIA - CNRS - LIX - LRI - PPS - Copyright 1999-2012     *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)
open Errors
open Names
open Term
open Univ
open Pre_env
open Reduction
open Nativelib
open Declarations
open Util
open Nativevalues
open Nativelambda
open Nativecode 

let rec conv_val pb lvl v1 v2 cu = 
  if v1 == v2 then cu
  else
    match kind_of_value v1, kind_of_value v2 with
    | Vaccu k1, Vaccu k2 ->
	conv_accu pb lvl k1 k2 cu
    | Vfun f1, Vfun f2 ->
	let v = mk_rel_accu lvl in
	conv_val CONV (lvl+1) (f1 v) (f2 v) cu
    | Vconst i1, Vconst i2 -> 
	if i1 = i2 then cu else raise NotConvertible
    | Vblock b1, Vblock b2 ->
	let n1 = block_size b1 in
	if block_tag b1 <> block_tag b2 || n1 <> block_size b2 then
	  raise NotConvertible;
	let rec aux lvl max b1 b2 i cu =
	  if i = max then 
	    conv_val CONV lvl (block_field b1 i) (block_field b2 i) cu
	  else
	    let cu = 
	      conv_val CONV lvl (block_field b1 i) (block_field b2 i) cu in
	    aux lvl max b1 b2 (i+1) cu in
	aux lvl (n1-1) b1 b2 0 cu
    | Varray t1, Varray t2 ->
	let len = Parray.length t1 in
	if not (Uint63.eq len (Parray.length t2)) then raise NotConvertible;
	let len = Uint63.to_int len in (* FIXME: use an iterator below instead *)
	let rec aux lvl len t1 t2 i cu =
	  if i = len then
	    conv_val CONV lvl
	      (Parray.default t1) (Parray.default t2) cu
	  else
	    let cu = 
	      let i = Uint63.of_int i in
              conv_val CONV lvl 
		(Parray.get t1 i) (Parray.get t2 i) cu in
	    aux lvl len t1 t2 (i+1) cu in
	aux lvl len t1 t2 0 cu
    | Vfun f1, _ -> 
	conv_val CONV lvl v1 (fun x -> v2 x) cu
    | _, Vfun f2 ->
	conv_val CONV lvl (fun x -> v1 x) v2 cu
    | _, _ -> raise NotConvertible

and conv_accu pb lvl k1 k2 cu = 
  let n1 = accu_nargs k1 in
  if n1 <> accu_nargs k2 then raise NotConvertible;
  if n1 = 0 then 
    conv_atom pb lvl (atom_of_accu k1) (atom_of_accu k2) cu
  else
    let cu = conv_atom pb lvl (atom_of_accu k1) (atom_of_accu k2) cu in
    List.fold_right2 (conv_val CONV lvl) (args_of_accu k1) (args_of_accu k2) cu

and conv_atom pb lvl a1 a2 cu =
  if a1 == a2 then cu
  else
    match a1, a2 with
    | Arel i1, Arel i2 -> 
	if i1 <> i2 then raise NotConvertible;
	cu
    | Aind ind1, Aind ind2 ->
	if not (eq_ind ind1 ind2) then raise NotConvertible;
	cu
    | Aconstant c1, Aconstant c2 ->
	if not (eq_constant c1 c2) then raise NotConvertible;
	cu
    | Asort s1, Asort s2 -> 
	sort_cmp pb s1 s2 cu
    | Avar id1, Avar id2 ->
	if id1 <> id2 then raise NotConvertible;
	cu
    | Acase(a1,ac1,p1,bs1), Acase(a2,ac2,p2,bs2) ->
	if a1.asw_ind <> a2.asw_ind then raise NotConvertible;
	let cu = conv_accu CONV lvl ac1 ac2 cu in
	let tbl = a1.asw_reloc in
	let len = Array.length tbl in
	if len = 0 then conv_val CONV lvl p1 p2 cu 
	else
	  let cu = conv_val CONV lvl p1 p2 cu in
	  let max = len - 1 in
	  let rec aux i cu =
	    let tag,arity = tbl.(i) in
	    let ci = 
	      if arity = 0 then mk_const tag
	      else mk_block tag (mk_rels_accu lvl arity) in
	    let bi1 = bs1 ci and bi2 = bs2 ci in
	    if i = max then conv_val CONV (lvl + arity) bi1 bi2 cu
	    else aux (i+1) (conv_val CONV (lvl + arity) bi1 bi2 cu) in
	  aux 0 cu
    | Afix(t1,f1,rp1,s1), Afix(t2,f2,rp2,s2) ->
	if s1 <> s2 || rp1 <> rp2 then raise NotConvertible;
	if f1 == f2 then cu
	else conv_fix lvl t1 f1 t2 f2 cu
    | (Acofix(t1,f1,s1,_) | Acofixe(t1,f1,s1,_)),
      (Acofix(t2,f2,s2,_) | Acofixe(t2,f2,s2,_)) ->
	if s1 <> s2 then raise NotConvertible;
	if f1 == f2 then cu
	else
	  if Array.length f1 <> Array.length f2 then raise NotConvertible
	  else conv_fix lvl t1 f1 t2 f2 cu 
    | Aprod(_,d1,c1), Aprod(_,d2,c2) ->
	let cu = conv_val CONV lvl d1 d2 cu in
	let v = mk_rel_accu lvl in
	conv_val pb (lvl + 1) (d1 v) (d2 v) cu 
    | _, _ -> raise NotConvertible

(* Precondition length t1 = length f1 = length f2 = length t2 *)
and conv_fix lvl t1 f1 t2 f2 cu =
  let len = Array.length f1 in
  let max = len - 1 in
  let fargs = mk_rels_accu lvl len in
  let flvl = lvl + len in
  let rec aux i cu =
    let cu = conv_val CONV lvl t1.(i) t2.(i) cu in
    let fi1 = napply f1.(i) fargs in
    let fi2 = napply f2.(i) fargs in
    if i = max then conv_val CONV flvl fi1 fi2 cu 
    else aux (i+1) (conv_val CONV flvl fi1 fi2 cu) in
  aux 0 cu

let nconv pb env t1 t2 =
  if !Flags.no_native_compiler then begin
    let msg = "Native compiler is disabled, "^
    "falling back to VM conversion test." in
    Pp.msg_warning (Pp.str msg);
    vm_conv pb env t1 t2
  end
  else
  let env = Environ.pre_env env in 
  let ml_filename, prefix = get_ml_filename () in
  let code, upds = mk_conv_code env prefix t1 t2 in
  match compile ml_filename code with
  | (true,fn) ->
      begin
        print_endline "Running test...";
        let t0 = Sys.time () in
        call_linker prefix fn (Some upds);
        let t1 = Sys.time () in
        Format.eprintf "Evaluation done in %.5f@." (t1 -. t0);
        (* TODO change 0 when we can have deBruijn *)
        conv_val pb 0 !rt1 !rt2 empty_constraint
      end
  | _ -> anomaly "Compilation failure" 

let _ = set_nat_conv nconv
