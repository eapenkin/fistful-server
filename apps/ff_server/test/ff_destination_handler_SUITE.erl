-module(ff_destination_handler_SUITE).

-include_lib("fistful_proto/include/ff_proto_destination_thrift.hrl").

-export([all/0]).
-export([groups/0]).
-export([init_per_suite/1]).
-export([end_per_suite/1]).
-export([init_per_group/2]).
-export([end_per_group/2]).
-export([init_per_testcase/2]).
-export([end_per_testcase/2]).

-export([create_destination_ok/1]).
% -export([create_wallet_identity_fails/1]).
% -export([create_wallet_currency_fails/1]).

-type config()         :: ct_helper:config().
-type test_case_name() :: ct_helper:test_case_name().
-type group_name()     :: ct_helper:group_name().
-type test_return()    :: _ | no_return().

-spec all() -> [test_case_name() | {group, group_name()}].

all() ->
    [{group, default}].

-spec groups() -> [{group_name(), list(), [test_case_name()]}].

groups() ->
    [
        {default, [parallel], [
            create_destination_ok
        ]}
    ].

-spec init_per_suite(config()) -> config().

init_per_suite(C) ->
    ct_helper:makeup_cfg([
        ct_helper:test_case_name(init),
        ct_payment_system:setup()
    ], C).

-spec end_per_suite(config()) -> _.

end_per_suite(C) ->
    ok = ct_payment_system:shutdown(C).

%%

-spec init_per_group(group_name(), config()) -> config().

init_per_group(_, C) ->
    C.

-spec end_per_group(group_name(), config()) -> _.

end_per_group(_, _) ->
    ok.
%%

-spec init_per_testcase(test_case_name(), config()) -> config().

init_per_testcase(Name, C) ->
    C1 = ct_helper:makeup_cfg([ct_helper:test_case_name(Name), ct_helper:woody_ctx()], C),
    ok = ff_woody_ctx:set(ct_helper:get_woody_ctx(C1)),
    C1.

-spec end_per_testcase(test_case_name(), config()) -> _.

end_per_testcase(_Name, _C) ->
    ok = ff_woody_ctx:unset().


-spec create_destination_ok(config()) -> test_return().

create_destination_ok(C) ->
    Party = create_party(C),
    Currency = <<"RUB">>,
    DstName = <<"loSHara card">>,
    ID = genlib:unique(),
    ExternalId = genlib:unique(),
    IdentityID = create_person_identity(Party, C),
    Resource = {bank_card, #'BankCard'{
        token = <<"TOKEN shmOKEN">>
    }},
    Ctx = #{<<"TEST_NS">> => {obj, #{ {str, <<"KEY">>} => {b, true} }}},
    Params = #dst_DestinationParams{
        id          = ID,
        identity_id = IdentityID,
        name        = DstName,
        currency    = Currency,
        resource    = Resource,
        external_id = ExternalId,
        context     = Ctx
    },
    {ok, DstState}  = call_service('Create', [Params]),
    DstName     = DstState#dst_DestinationState.name,
    ID          = DstState#dst_DestinationState.id,
    IdentityID  = DstState#dst_DestinationState.identity,
    Currency    = DstState#dst_DestinationState.currency,
    Resource    = DstState#dst_DestinationState.resource,
    Ctx         = DstState#dst_DestinationState.context,
    {unauthorized, #dst_Unauthorized{}} = DstState#dst_DestinationState.status,
    ok.

%%-----------
%%  Internal
%%-----------
call_service(Fun, Args) ->
    Service = {ff_proto_destination_thrift, 'Management'},
    Request = {Service, Fun, Args},
    Client  = ff_woody_client:new(#{
        url           => <<"http://localhost:8022/v1/destination">>,
        event_handler => scoper_woody_event_handler
    }),
    ff_woody_client:call(Client, Request).


create_party(_C) ->
    ID = genlib:bsuuid(),
    _ = ff_party:create(ID),
    ID.

create_person_identity(Party, C) ->
    create_identity(Party, <<"good-one">>, <<"person">>, C).

create_identity(Party, ProviderID, ClassID, _C) ->
    ID = genlib:unique(),
    ok = ff_identity_machine:create(
        ID,
        #{party => Party, provider => ProviderID, class => ClassID},
        ff_ctx:new()
    ),
    ID.