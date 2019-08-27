%%%
%%% Deposit machine
%%%

-module(ff_deposit_machine).

-behaviour(machinery).

%% API

-type id() :: machinery:id().
-type event() :: ff_deposit:event().
-type events() :: [{integer(), ff_machine:timestamped_event(event())}].
-type st() :: ff_machine:st(deposit()).
-type deposit() :: ff_deposit:deposit().
-type external_id() :: id().

-type params() :: ff_deposit:params().
-type create_error() ::
    ff_deposit:create_error() |
    exists.
-type start_revert_error() ::
    ff_deposit:start_revert_error() |
    unknown_deposit_error().

-type start_revert_adjustment_error() ::
    ff_deposit:start_revert_adjustment_error() |
    unknown_deposit_error().

-type unknown_deposit_error() ::
    {unknown_deposit, id()}.

-export_type([id/0]).
-export_type([st/0]).
-export_type([event/0]).
-export_type([events/0]).
-export_type([params/0]).
-export_type([deposit/0]).
-export_type([external_id/0]).
-export_type([create_error/0]).
-export_type([start_revert_error/0]).
-export_type([start_revert_adjustment_error/0]).

%% API

-export([create/2]).
-export([get/1]).
-export([events/2]).

-export([start_revert/2]).
-export([start_revert_adjustment/3]).

%% Accessors

-export([deposit/1]).
-export([ctx/1]).

%% Machinery

-export([init/4]).
-export([process_timeout/3]).
-export([process_repair/4]).
-export([process_call/4]).

%% Pipeline

-import(ff_pipeline, [do/1, unwrap/1]).

%% Internal types

-type ctx()           :: ff_ctx:ctx().
-type revert_params() :: ff_deposit:revert_params().
-type revert_id()     :: ff_deposit_revert:id().

-type revert_adjustment_params() :: ff_deposit:revert_adjustment_params().

-type call() ::
    {start_revert, revert_params()}.

-define(NS, 'ff/deposit_v1').

%% API

-spec create(params(), ctx()) ->
    ok |
    {error, ff_deposit:create_error() | exists}.

create(Params, Ctx) ->
    do(fun () ->
        #{id := ID} = Params,
        Events = unwrap(ff_deposit:create(Params)),
        unwrap(machinery:start(?NS, ID, {Events, Ctx}, backend()))
    end).

-spec get(id()) ->
    {ok, st()} |
    {error, unknown_deposit_error()}.

get(ID) ->
    case ff_machine:get(ff_deposit, ?NS, ID) of
        {ok, _Machine} = Result ->
            Result;
        {error, notfound} ->
            {error, {unknown_deposit, ID}}
    end.

-spec events(id(), machinery:range()) ->
    {ok, events()} |
    {error, unknown_deposit_error()}.

events(ID, Range) ->
    case machinery:get(?NS, ID, Range, backend()) of
        {ok, #{history := History}} ->
            {ok, [{EventID, TsEv} || {EventID, _, TsEv} <- History]};
        {error, notfound} ->
            {error, {unknown_deposit, ID}}
    end.

-spec start_revert(id(), revert_params()) ->
    {ok, events()} |
    {error, start_revert_error()}.

start_revert(ID, Params) ->
    call(ID, {start_revert, Params}).

-spec start_revert_adjustment(id(), revert_id(), revert_adjustment_params()) ->
    {ok, events()} |
    {error, start_revert_adjustment_error()}.

start_revert_adjustment(DepositID, RevertID, Params) ->
    call(DepositID, {start_revert_adjustment, RevertID, Params}).

%% Accessors

-spec deposit(st()) ->
    deposit().

deposit(St) ->
    ff_machine:model(St).

-spec ctx(st()) ->
    ctx().

ctx(St) ->
    ff_machine:ctx(St).

%% Machinery

-type machine()      :: ff_machine:machine(event()).
-type result()       :: ff_machine:result(event()).
-type handler_opts() :: machinery:handler_opts(_).
-type handler_args() :: machinery:handler_args(_).

-spec init({[event()], ctx()}, machine(), handler_args(), handler_opts()) ->
    result().

init({Events, Ctx}, #{}, _, _Opts) ->
    #{
        events    => ff_machine:emit_events(Events),
        action    => continue,
        aux_state => #{ctx => Ctx}
    }.

-spec process_timeout(machine(), handler_args(), handler_opts()) ->
    result().

process_timeout(Machine, _, _Opts) ->
    St = ff_machine:collapse(ff_deposit, Machine),
    Deposit = deposit(St),
    process_result(ff_deposit:process_transfer(Deposit), St).

-spec process_call(call(), machine(), handler_args(), handler_opts()) -> {Response, result()} when
    Response :: ok | {error, ff_deposit:start_revert_error()}.

process_call({start_revert, Params}, Machine, _, _Opts) ->
    do_start_revert(Params, Machine);
process_call({start_revert_adjustment, RevertID, Params}, Machine, _, _Opts) ->
    do_start_revert_adjustment(RevertID, Params, Machine);
process_call(CallArgs, _Machine, _, _Opts) ->
    erlang:error({unexpected_call, CallArgs}).

-spec process_repair(ff_repair:scenario(), machine(), handler_args(), handler_opts()) ->
    result().

process_repair(Scenario, Machine, _Args, _Opts) ->
    ff_repair:apply_scenario(ff_deposit, Machine, Scenario).

%% Internals

backend() ->
    fistful:backend(?NS).

-spec do_start_revert(revert_params(), machine()) -> {Response, result()} when
    Response :: ok | {error, ff_deposit:start_revert_error()}.

do_start_revert(Params, Machine) ->
    St = ff_machine:collapse(ff_deposit, Machine),
    case ff_deposit:start_revert(Params, deposit(St)) of
        {ok, {Action, Events}} ->
            {ok, genlib_map:compact(#{
                events => set_events(Events),
                action => Action
            })};
        {error, _Reason} = Error ->
            {Error, #{}}
    end.

-spec do_start_revert_adjustment(revert_id(), revert_adjustment_params(), machine()) -> {Response, result()} when
    Response :: ok | {error, ff_deposit:start_revert_adjustment_error()}.

do_start_revert_adjustment(RevertID, Params, Machine) ->
    St = ff_machine:collapse(ff_deposit, Machine),
    case ff_deposit:start_revert_adjustment(RevertID, Params, deposit(St)) of
        {ok, {Action, Events}} ->
            {ok, genlib_map:compact(#{
                events => set_events(Events),
                action => Action
            })};
        {error, _Reason} = Error ->
            {Error, #{}}
    end.

process_result({ok, {Action, Events}}, _St) ->
    genlib_map:compact(#{
        events => set_events(Events),
        action => Action
    });
process_result({error, Reason}, St) ->
    {ok, {Action, Events}} = ff_deposit:process_failure(Reason, deposit(St)),
    genlib_map:compact(#{
        events => set_events(Events),
        action => Action
    }).

set_events([]) ->
    undefined;
set_events(Events) ->
    ff_machine:emit_events(Events).

call(ID, Call) ->
    case machinery:call(?NS, ID, Call, backend()) of
        {ok, Reply} ->
            Reply;
        {error, notfound} ->
            {error, {unknown_deposit, ID}}
    end.