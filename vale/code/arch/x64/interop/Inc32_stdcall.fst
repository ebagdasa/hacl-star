module Inc32_stdcall

open LowStar.Buffer
module B = LowStar.Buffer
module BV = LowStar.BufferView
open LowStar.Modifies
module M = LowStar.Modifies
open LowStar.ModifiesPat
open FStar.HyperStack.ST
module HS = FStar.HyperStack
open Interop
open Words_s
open Types_s
open X64.Machine_s
open X64.Memory_s
open X64.Vale.State
open X64.Vale.Decls
open BufferViewHelpers
open Interop_assumptions
open X64.Vale.StateLemmas
open X64.Vale.Lemmas
module TS = X64.Taint_Semantics_s
module ME = X64.Memory_s
module BS = X64.Bytes_Semantics_s

friend SecretByte
friend X64.Memory_s
friend X64.Memory
friend X64.Vale.Decls
friend X64.Vale.StateLemmas
#set-options "--z3rlimit 60"

open Vale_inc32_stdcall

#set-options "--initial_fuel 4 --max_fuel 4 --initial_ifuel 0 --max_ifuel 0"
let create_buffer_list (iv_b:s8) (stack_b:b8)  : (l:list b8{
    l == [stack_b;iv_b] /\
  (forall x. {:pattern List.memP x l} List.memP x l <==> (x == iv_b \/ x == stack_b))}) =
  [stack_b;iv_b]

#set-options "--max_fuel 0 --max_ifuel 0"

let create_initial_trusted_state is_win iv_b stack_b (h0:HS.mem{pre_cond h0 iv_b /\ B.length stack_b == 16 /\ live h0 stack_b /\ buf_disjoint_from stack_b [iv_b]}) : GTot TS.traceState =
  let taint_func (x:b8) : GTot taint =
    if StrongExcludedMiddle.strong_excluded_middle (x == iv_b) then Secret else
    Public in
  let buffers = create_buffer_list iv_b stack_b in
  let (mem:mem) = {addrs = addrs; ptrs = buffers; hs = h0} in
  let addr_iv_b = addrs iv_b in
  let addr_stack:nat64 = addrs stack_b + 0 in
  let regs = if is_win then (
    fun r -> begin match r with
    | Rsp -> addr_stack
    | Rcx -> addr_iv_b
    | _ -> init_regs r end)
  else (
    fun r -> begin match r with
    | Rsp -> addr_stack
    | Rdi -> addr_iv_b
    | _ -> init_regs r end)
  in let regs = FunctionalExtensionality.on reg regs
  in let xmms = FunctionalExtensionality.on xmm init_xmms in
  let (s0:BS.state) = {BS.ok = true; BS.regs = regs; BS.xmms = xmms; BS.flags = 0;
       BS.mem = Interop.down_mem h0 addrs buffers} in
  {TS.state = s0; TS.trace = []; TS.memTaint = create_valid_memtaint mem buffers taint_func}

val lemma_ghost_inc32_stdcall: is_win:bool -> iv_b:s8 ->  stack_b:b8 -> (h0:HS.mem{pre_cond h0 iv_b /\ B.length stack_b == 16 /\ live h0 stack_b /\ buf_disjoint_from stack_b [iv_b]}) ->
  Ghost (TS.traceState * nat * HS.mem)
    (requires True)
    (ensures (fun (s1, f1, h1) ->
      (let s0 = create_initial_trusted_state is_win iv_b stack_b h0 in
      Some s1 == TS.taint_eval_code (va_code_inc32_stdcall is_win) f1 s0 /\
      Interop.correct_down h1 addrs [stack_b;iv_b] s1.TS.state.BS.mem /\
      post_cond h0 h1 iv_b  /\
      calling_conventions is_win s0 s1 /\
      M.modifies (M.loc_union (M.loc_buffer stack_b) ( M.loc_buffer iv_b)) h0 h1)
    ))

// ===============================================================================================
//  Everything below this line is untrusted

let create_initial_vale_state is_win iv_b stack_b (h0:HS.mem{pre_cond h0 iv_b /\ B.length stack_b == 16 /\ live h0 stack_b /\ buf_disjoint_from stack_b [iv_b]}) : GTot va_state =
  let taint_func (x:b8) : GTot taint =
    if StrongExcludedMiddle.strong_excluded_middle (x == iv_b) then Secret else
    Public in
  let buffers = create_buffer_list iv_b stack_b in
  let (mem:mem) = {addrs = addrs; ptrs = buffers; hs = h0} in
  let addr_iv_b = addrs iv_b in
  let addr_stack:nat64 = addrs stack_b + 0 in
  let regs = if is_win then (
    fun r -> begin match r with
    | Rsp -> addr_stack
    | Rcx -> addr_iv_b
    | _ -> init_regs r end)
  else (
    fun r -> begin match r with
    | Rsp -> addr_stack
    | Rdi -> addr_iv_b
    | _ -> init_regs r end)
  in let regs = X64.Vale.Regs.of_fun regs
  in let xmms = X64.Vale.Xmms.of_fun init_xmms in
  {ok = true; regs = regs; xmms = xmms; flags = 0; mem = mem;
      memTaint = create_valid_memtaint mem buffers taint_func}

let create_lemma is_win iv_b stack_b (h0:HS.mem{pre_cond h0 iv_b /\ B.length stack_b == 16 /\ live h0 stack_b /\ buf_disjoint_from stack_b [iv_b]}) : Lemma
  (create_initial_trusted_state is_win iv_b stack_b h0 == state_to_S (create_initial_vale_state is_win iv_b stack_b h0)) =
    let s_init = create_initial_trusted_state is_win iv_b stack_b h0 in
    let s0 = create_initial_vale_state is_win iv_b stack_b h0 in
    let s1 = state_to_S s0 in
    assert (FunctionalExtensionality.feq (regs' s1.TS.state) (regs' s_init.TS.state));
    assert (FunctionalExtensionality.feq (xmms' s1.TS.state) (xmms' s_init.TS.state))

let implies_pre (is_win:bool) (h0:HS.mem) (iv_b:s8)  (stack_b:b8) : Lemma
  (requires pre_cond h0 iv_b /\ B.length stack_b == 16 /\ live h0 stack_b /\ buf_disjoint_from stack_b [iv_b])
  (ensures (
B.length stack_b == 16 /\ live h0 stack_b /\ buf_disjoint_from stack_b [iv_b] /\ (
  let s0 = create_initial_vale_state is_win iv_b stack_b h0 in
  length_t_eq (TBase TUInt64) stack_b;
  length_t_eq (TBase TUInt128) iv_b;
  va_pre (va_code_inc32_stdcall is_win) s0 is_win stack_b iv_b ))) =
  length_t_eq (TBase TUInt64) stack_b;
  length_t_eq (TBase TUInt128) iv_b;
  assert(Interop.disjoint stack_b iv_b);
  ()

let implies_post (is_win:bool) (va_s0:va_state) (va_sM:va_state) (va_fM:va_fuel) (iv_b:s8)  (stack_b:b8) : Lemma
  (requires pre_cond va_s0.mem.hs iv_b /\ B.length stack_b == 16 /\ live va_s0.mem.hs stack_b /\ buf_disjoint_from stack_b [iv_b]/\
    va_post (va_code_inc32_stdcall is_win) va_s0 va_sM va_fM is_win stack_b iv_b )
  (ensures post_cond va_s0.mem.hs va_sM.mem.hs iv_b ) =
  length_t_eq (TBase TUInt64) stack_b;
  length_t_eq (TBase TUInt128) iv_b;
  let iv128_b = BV.mk_buffer_view iv_b Views.view128 in
  assert (Seq.equal (buffer_as_seq (va_get_mem va_sM) iv_b) (BV.as_seq va_sM.mem.hs iv128_b));
  BV.as_seq_sel va_sM.mem.hs iv128_b 0;
  assert (Seq.equal (buffer_as_seq (va_get_mem va_s0) iv_b) (BV.as_seq va_s0.mem.hs iv128_b));
  BV.as_seq_sel va_s0.mem.hs iv128_b 0;  
  ()

#set-options "--max_fuel 0 --initial_ifuel 1 --max_ifuel 1"

let lemma_ghost_inc32_stdcall is_win iv_b stack_b h0 =
  length_t_eq (TBase TUInt64) stack_b;
  length_t_eq (TBase TUInt128) iv_b;
  implies_pre is_win h0 iv_b stack_b;
  let s0 = create_initial_trusted_state is_win iv_b stack_b h0 in
  let s0' = create_initial_vale_state is_win iv_b stack_b h0 in
  create_lemma is_win iv_b stack_b h0;
  let s_v, f_v = va_lemma_inc32_stdcall (va_code_inc32_stdcall is_win) s0' is_win stack_b iv_b in
  implies_post is_win s0' s_v f_v iv_b stack_b;
  let s1 = Some?.v (TS.taint_eval_code (va_code_inc32_stdcall is_win) f_v s0) in
  assert (state_eq_S s1 (state_to_S s_v));
  assert (FunctionalExtensionality.feq s1.TS.state.BS.regs (X64.Vale.Regs.to_fun s_v.regs));
  assert (FunctionalExtensionality.feq s1.TS.state.BS.xmms (X64.Vale.Xmms.to_fun s_v.xmms));
  assert (M.modifies (M.loc_union (M.loc_buffer stack_b) ( M.loc_buffer iv_b)) h0 s_v.mem.hs);
  s1, f_v, s_v.mem.hs

#set-options "--max_fuel 0 --max_ifuel 0"

irreducible
let inc32_stdcall_aux (iv_b:s8) (stack_b:b8) : Stack unit
  (fun h -> pre_cond h iv_b  /\ B.length stack_b == 16 /\ live h stack_b /\ buf_disjoint_from stack_b [iv_b])
  (fun h0 _ h1 ->
    post_cond h0 h1 iv_b  /\
    M.modifies (M.loc_union (M.loc_buffer stack_b) ( M.loc_buffer iv_b)) h0 h1) =
  if win then
  st_put
    (fun h -> pre_cond h iv_b /\ B.length stack_b == 16 /\ live h stack_b /\ buf_disjoint_from stack_b [iv_b])
    (fun h -> let _, _, h1 =
      lemma_ghost_inc32_stdcall true iv_b stack_b h
    in (), h1)
  else st_put
    (fun h -> pre_cond h iv_b /\ B.length stack_b == 16 /\ live h stack_b /\ buf_disjoint_from stack_b [iv_b])
    (fun h -> let _, _, h1 =
      lemma_ghost_inc32_stdcall false iv_b stack_b h
    in (), h1)

let inc32_stdcall iv_b  =
  push_frame();
  let (stack_b:b8) = B.alloca (UInt8.uint_to_t 0) (UInt32.uint_to_t 16) in
  inc32_stdcall_aux iv_b stack_b;
  pop_frame()
