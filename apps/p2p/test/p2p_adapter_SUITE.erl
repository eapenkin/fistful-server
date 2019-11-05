-module(p2p_adapter_SUITE).

-include_lib("stdlib/include/assert.hrl").
-include_lib("common_test/include/ct.hrl").
-include_lib("damsel/include/dmsl_domain_thrift.hrl").
-include_lib("damsel/include/dmsl_p2p_adapter_thrift.hrl").

-export([all/0]).
-export([init_per_suite/1]).
-export([end_per_suite/1]).
-export([init_per_testcase/2]).
-export([end_per_testcase/2]).

-export([process/1]).
-export([handle_callback/1]).

-type config()         :: ct_helper:config().
-type test_case_name() :: ct_helper:test_case_name().
-type group_name()     :: ct_helper:group_name().
-type test_return()    :: ok | no_return().

-spec all() -> [test_case_name() | {group, group_name()}].
all() -> [
        process,
        handle_callback
    ].

-spec init_per_suite(config()) -> config().
init_per_suite(C) ->
    ct_helper:makeup_cfg([
        ct_helper:test_case_name(init),
        ct_payment_system:setup(#{})
    ], C).

-spec end_per_suite(config()) -> ok.
end_per_suite(C) ->
    ok = ct_payment_system:shutdown(C).

-spec init_per_testcase(test_case_name(), config()) -> config().

init_per_testcase(Name, C) ->
    C1 = ct_helper:makeup_cfg([ct_helper:test_case_name(Name), ct_helper:woody_ctx()], C),
    ok = ct_helper:set_context(C1),
    C1.

-spec end_per_testcase(test_case_name(), config()) -> _.

end_per_testcase(_Name, _C) ->
    ok = ct_helper:unset_context().

-spec process(config()) -> test_return().
process(_C) ->
    Adapter        = ff_woody_client:new(<<"http://localhost:8222/p2p_adapter">>),
    TransferParams = construct_transfer_params(),
    AdapterState   = <<>>,
    AdapterOpts    = #{},
    Result         = p2p_adapter:process(Adapter, TransferParams, AdapterState, AdapterOpts),
    ?assertMatch({ok, {{finish, success}, #{}}}, Result),
    ok.

-spec handle_callback(config()) -> test_return().
handle_callback(_C) ->
    Adapter  = ff_woody_client:new(<<"http://localhost:8222/p2p_adapter">>),
    TransferParams = construct_transfer_params(),
    AdapterState   = <<>>,
    AdapterOpts    = #{},
    Callback       = #{tag => <<"p2p">>, payload => <<>>},
    Result         = p2p_adapter:handle_callback(Adapter, Callback, TransferParams, AdapterState, AdapterOpts),
    ?assertMatch({ok, {{finish, success}, <<"payload">>, #{}}}, Result),
    ok.

construct_transfer_params() ->
    #{
        id            => <<"1">>,
        cash          => {10, <<"USD">>},
        sender        => construct_resource(),
        receiver      => construct_resource(),
        deadline      => <<>>
    }.

construct_resource() ->
    {raw_full, #{
        token          => <<"token">>,
        bin            => <<"bin">>,
        payment_system => visa,
        masked_pan     => <<"masked_pan">>
    }}.