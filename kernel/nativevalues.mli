(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, *   INRIA - CNRS - LIX - LRI - PPS - Copyright 1999-2012     *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)
open Term
open Names

type t = t -> t

type accumulator

type tag = int
type arity = int

type reloc_table = (tag * arity) array

type annot_sw = {
    asw_ind : inductive;
    asw_ci : case_info;
    asw_reloc : reloc_table;
    asw_finite : bool;
    asw_prefix : string
  }

type sort_annot = string * int
      
type rec_pos = int array

type atom =
  | Arel of int
  | Aconstant of constant
  | Aind of inductive
  | Asort of sorts
  | Avar of identifier
  | Acase of annot_sw * accumulator * t * (t -> t) 
  | Afix of t array * t array * rec_pos * int 
  | Acofix of t array * t array * int * t
  | Acofixe of t array * t array * int * t
  | Aprod of name * t * (t -> t)

(* Constructors *)

val mk_accu : atom -> t
val mk_rel_accu : int -> t
val mk_rels_accu : int -> int -> t array
val mk_constant_accu : constant -> t
val mk_ind_accu : inductive -> t
val mk_sort_accu : sorts -> t
val mk_var_accu : identifier -> t
val mk_sw_accu : annot_sw -> accumulator -> t -> (t -> t)
val mk_prod_accu : name -> t -> t -> t
val mk_fix_accu : rec_pos  -> int -> t array -> t array -> t
val mk_cofix_accu : int -> t array -> t array -> t 
val upd_cofix : t -> t -> unit
val force_cofix : t -> t 
val mk_const : tag -> t
val mk_block : tag -> t array -> t


val mk_int : int -> t
val mk_uint : Uint63.t -> t
val mk_resource : Resource.t -> t
val is_resource : 'a -> bool
val napply : t -> t array -> t
(* Functions over accumulators *)

val dummy_value : unit -> t
val atom_of_accu : accumulator -> atom
val args_of_accu : accumulator -> t list
val accu_nargs : accumulator -> int

val cast_accu : 'a -> accumulator
(* Functions over block: i.e constructors *)
    
type block
      
val block_size : block -> int
val block_field : block -> int -> t
val block_tag : block -> int



(* kind_of_value *)

type kind_of_value =
  | Vaccu of accumulator
  | Vfun of (t -> t)
  | Vconst of int
  | Vblock of block
  | Vint of Uint63.t
  | Varray of t Parray.t 

val kind_of_value : t -> kind_of_value

(* *)
val is_accu : t -> bool

(*** Primitive on int63 *)

val of_bool : bool -> t
val is_int : t -> bool

(* function with check *)
val head0 : t -> t
val tail0 : t -> t

val add : t -> t -> t
val sub : t -> t -> t
val mul : t -> t -> t
val div : t -> t -> t
val rem : t -> t -> t

val l_sr  : t -> t -> t
val l_sl  : t -> t -> t
val l_and : t -> t -> t
val l_xor : t -> t -> t
val l_or  : t -> t -> t

val addc      : t -> t -> t
val subc      : t -> t -> t
val addCarryC : t -> t -> t
val subCarryC : t -> t -> t

val mulc    : t -> t -> t
val diveucl : t -> t -> t

val div21     : t -> t -> t -> t
val addMulDiv : t -> t -> t -> t

val eq      : t -> t -> t
val lt      : t -> t -> t
val le      : t -> t -> t
val compare : t -> t -> t 

val eqb_correct : t -> t -> t -> t

val print : t -> t
val foldi : t -> t -> t -> t -> t
val foldi_down : t -> t -> t -> t -> t

val arraymake    : t -> t -> t      (* accu A n def *)
val arrayget     : t -> t -> t      (* accu A t n *)
val arraydefault : t -> t           (* accu A t *)
val arrayset     : t -> t -> t -> t (* accu A t n v *)
val arraydestrset : t -> t -> t -> t (* accu A t n v *)
val arraycopy    : t -> t           (* accu A t *)
val arrayreroot  : t -> t           (* accu A t *)
val arraylength  : t -> t           (* accu A t *)
val arrayinit    : t -> t -> t -> t (* accu A n f def *)
val arraymap     : t -> t -> t (* accu A B f t *)

val lt_b : t -> t -> bool
val le_b : t -> t -> bool

val parray_of_array : t array -> t
val is_parray : t -> bool

val resourcegeti : t -> t -> t
val resourcegetc : t -> t -> t
val check_resource_name : t -> bool
val resourcemake : t -> t

val str_encode : 'a -> string
val str_decode : string -> 'a
