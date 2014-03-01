-module(stream_worker_tests).
%% run with: "./rebar compile eunit skip_deps=true"

-include_lib("pkt/include/pkt.hrl").
-include_lib("eunit/include/eunit.hrl").
-include("../include/stream_lib.hrl").


stream_worker_test_() ->
    [
     compare_32_1(),
     compare_32_2(),
     compare_32_3(),
     compare_32_4(),
     compare_32_5(),
     compare_32_6(),
     compare_32_7(),
     compare_32_8(),
     smaller32_1(),
     smaller32_2(),
     smaller32_3(),
     smaller32_4(),
     smaller32_5(),
     smaller32_6(),
     smaller_or_equal32_1(),
     smaller_or_equal32_2(),
     smaller_or_equal32_3(),
     smaller_or_equal32_4(),
     smaller_or_equal32_5(),
     smaller_or_equal32_6(),
     acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_1(),
     acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_2(),
     acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_3(),
     acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_5(),
     acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_6(),
     acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_7(),
     acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_8(),
     acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_9(),
     acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_10(),
     acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_11(),
     acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_12(),
     acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_13(),
     acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_14(),
     acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_15(),
     acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_16(),
     acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_17(),
     acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_18(),
     acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_19(),
     acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_20(),
     acknowledgePayloadReceptionBuffer_always_favour_old_data_1(), 
     acknowledgePayloadReceptionBuffer_always_favour_old_data_2(), 
     acknowledgePayloadReceptionBuffer_always_favour_old_data_3(),
     acknowledgePayloadReceptionBuffer_always_favour_old_data_4(),
     acknowledgePayloadReceptionBuffer_always_favour_old_data_5(),
     acknowledgePayloadReceptionBuffer_always_favour_old_data_6(),
     acknowledgePayloadReceptionBuffer_always_favour_old_data_7(),
     acknowledgePayloadReceptionBuffer_always_favour_old_data_8(),
     acknowledgePayloadReceptionBuffer_always_favour_old_data_9(),
     acknowledgePayloadReceptionBuffer_always_favour_old_data_10(),
     acknowledgePayloadReceptionBuffer_always_favour_old_data_11(),
     acknowledgePayloadReceptionBuffer_always_favour_old_data_12(),
     acknowledgePayloadReceptionBuffer_always_favour_old_data_13(),
     acknowledgePayloadReceptionBuffer_always_favour_old_data_14(),
     acknowledgePayloadReceptionBuffer_always_favour_old_data_15(),
     acknowledgePayloadReceptionBuffer_always_favour_old_data_16(),
     acknowledgePayloadReceptionBuffer_always_favour_old_data_16(),
     acknowledgePayloadReceptionBuffer_always_favour_old_data_17(),
     acknowledgePayloadReceptionBuffer_always_favour_old_data_18(),
     acknowledgePayloadReceptionBuffer_always_favour_old_data_19(),
     acknowledgePayloadReceptionBuffer_always_favour_old_data_20(),
     checkSAckReceptionBuffer_favour_new_data_for_forward_overlap_1(),
     checkSAckReceptionBuffer_favour_new_data_for_forward_overlap_2(),
     checkSAckReceptionBuffer_favour_new_data_for_forward_overlap_3(),
     get_first_element_1(),
     get_first_element_2(),
     get_first_element_3(),
     get_first_element_4(),
     get_first_element_5(),
     get_first_element_6(),
     get_first_element_7(),
     get_first_element_8(),
     get_first_element_SEG_ACK_RCV_NXT_1(),
     get_first_element_SEG_ACK_RCV_NXT_2(),
     get_first_element_SEG_ACK_RCV_NXT_3(),
     get_first_element_SEG_ACK_RCV_NXT_4(),
     get_first_element_SEG_ACK_RCV_NXT_5(),
     get_first_element_SEG_ACK_RCV_NXT_6(),
     get_first_element_SEG_ACK_RCV_NXT_7(),
     get_first_element_SEG_ACK_RCV_NXT_8()
    ].

compare_32_1() ->
    ?_assertEqual(
       '<', stream_lib:compare_32(1,2)
      ).

compare_32_2() ->
    ?_assertEqual(
       '<', stream_lib:compare_32(16#FFFFFFFF-1,16#FFFFFFFF)
      ).

compare_32_3() ->
    ?_assertEqual(
       '<', stream_lib:compare_32(16#FFFFFFFF,0)
      ).

compare_32_4() ->
    ?_assertEqual(
       '>', stream_lib:compare_32(2,1)
      ).

compare_32_5() ->
    ?_assertEqual(
       '>', stream_lib:compare_32(16#FFFFFFFF,16#FFFFFFFF-1)
      ).

compare_32_6()->
    ?_assertEqual(
       '==', stream_lib:compare_32(16#FFFFFFFF,16#FFFFFFFF)
      ).

compare_32_7()->
    ?_assertEqual(
       '<', stream_lib:compare_32(4294529824, 504)
      ).

compare_32_8()->
    ?_assertEqual(
       '>', stream_lib:compare_32(504, 4294529824)
      ).

smaller32_1() ->
    ?_assertEqual(
       true, stream_worker:smaller32(1,2)
      ).

smaller32_2() ->
    ?_assertEqual(
       true, stream_worker:smaller32(16#FFFFFFFF-1,16#FFFFFFFF)
      ).

smaller32_3() ->
    ?_assertEqual(
       true, stream_worker:smaller32(16#FFFFFFFF,0)
      ).

smaller32_4() ->
    ?_assertEqual(
       false, stream_worker:smaller32(2,1)
      ).

smaller32_5() ->
    ?_assertEqual(
       false, stream_worker:smaller32(16#FFFFFFFF,16#FFFFFFFF-1)
      ).

smaller32_6()->
    ?_assertEqual(
       false, stream_worker:smaller32(16#FFFFFFFF,16#FFFFFFFF)
      ).

smaller_or_equal32_1() ->
    ?_assertEqual(
       true, stream_worker:smaller_or_equal32(1,2)
      ).

smaller_or_equal32_2() ->
    ?_assertEqual(
       true, stream_worker:smaller_or_equal32(16#FFFFFFFF-1,16#FFFFFFFF)
      ).

smaller_or_equal32_3() ->
    ?_assertEqual(
       true, stream_worker:smaller_or_equal32(16#FFFFFFFF,0)
      ).

smaller_or_equal32_4() ->
    ?_assertEqual(
       false, stream_worker:smaller_or_equal32(2,1)
      ).

smaller_or_equal32_5() ->
    ?_assertEqual(
       false, stream_worker:smaller_or_equal32(16#FFFFFFFF,16#FFFFFFFF-1)
      ).

smaller_or_equal32_6()->
    ?_assertEqual(
       true, stream_worker:smaller_or_equal32(16#FFFFFFFF,16#FFFFFFFF)
      ).

acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_1() ->
    ForwardOverlapStrategy = favour_new_data_for_forward_overlap,
    B1 = #packet{seg_seq = 5000, payload_size = 1, payload= <<"A">>},
    B2 = #packet{seg_seq = 5001, payload_size = 1, payload= <<"T">>},
    B3 = #packet{seg_seq = 5002, payload_size = 1, payload= <<"T">>},
    B4 = #packet{seg_seq = 5003, payload_size = 1, payload= <<"A">>},
    B5 = #packet{seg_seq = 5005, payload_size = 1, payload= <<"K">>},
    B6 = #packet{seg_seq = 5004, payload_size = 2, payload= <<"CH">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    A4 = stream_lib:insert(B3, A3, ForwardOverlapStrategy),
    A5 = stream_lib:insert(B4, A4, ForwardOverlapStrategy),
    A6 = stream_lib:insert(B5, A5, ForwardOverlapStrategy),
    A7 = stream_lib:insert(B6, A6, ForwardOverlapStrategy),
    {_Left, _Right} = A7,
    Result = A7,
    ?_assertEqual({[
		    B6#packet{seg_seq = 5005, payload_size = 1, payload= <<"H">>}, 
		    B5#packet{seg_seq = 5004, payload_size = 1, payload= <<"C">>}, B4, B3, B2, B1],[]}, Result).

acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_2() ->
    ForwardOverlapStrategy = favour_new_data_for_forward_overlap,
    B1 = #packet{seg_seq = 5000, payload_size = 1, payload= <<"A">>},
    B2 = #packet{seg_seq = 5001, payload_size = 1, payload= <<"T">>},
    B3 = #packet{seg_seq = 5002, payload_size = 1, payload= <<"T">>},
    B4 = #packet{seg_seq = 5003, payload_size = 1, payload= <<"A">>},
    B5 = #packet{seg_seq = 5005, payload_size = 1, payload= <<"K">>},
    B6 = #packet{seg_seq = 5003, payload_size = 2, payload= <<"IC">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    A4 = stream_lib:insert(B3, A3, ForwardOverlapStrategy),
    A5 = stream_lib:insert(B4, A4, ForwardOverlapStrategy),
    A6 = stream_lib:insert(B5, A5, ForwardOverlapStrategy),
    A7 = stream_lib:insert(B6, A6, ForwardOverlapStrategy),
    {_Left, _Right} = A7,
    Result = A7,
    ?_assertEqual({[B5#packet{seg_seq = 5004, payload_size = 1, payload= <<"C">>}, B4, B3, B2, B1],
                   [B6#packet{seg_seq = 5005, payload_size = 1, payload= <<"K">>}]}, Result).

acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_3() ->
    ForwardOverlapStrategy = favour_new_data_for_forward_overlap,
    B1 = #packet{seg_seq = 5000, payload_size = 1, payload= <<"A">>},
    B2 = #packet{seg_seq = 5001, payload_size = 1, payload= <<"T">>},
    B3 = #packet{seg_seq = 5002, payload_size = 1, payload= <<"T">>},
    B4 = #packet{seg_seq = 5003, payload_size = 1, payload= <<"A">>},
    B5 = #packet{seg_seq = 5005, payload_size = 1, payload= <<"K">>},
    B6 = #packet{seg_seq = 5004, payload_size = 3, payload= <<"CHI">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    A4 = stream_lib:insert(B3, A3, ForwardOverlapStrategy),
    A5 = stream_lib:insert(B4, A4, ForwardOverlapStrategy),
    A6 = stream_lib:insert(B5, A5, ForwardOverlapStrategy),
    A7 = stream_lib:insert(B6, A6, ForwardOverlapStrategy),
    {_Left, _Right} = A7,
    Result = A7,
    ?_assertEqual({[
                    B6#packet{seg_seq = 5006, payload_size = 1, payload= <<"I">>},
		    B6#packet{seg_seq = 5005, payload_size = 1, payload= <<"H">>}, 
		    B5#packet{seg_seq = 5004, payload_size = 1, payload= <<"C">>}, B4, B3, B2, B1],[]}, Result).


acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_5() ->
    ForwardOverlapStrategy = favour_new_data_for_forward_overlap,
    B1 = #packet{seg_seq = 5000, payload_size = 2, payload= <<"12">>},
    B2 = #packet{seg_seq = 5001, payload_size = 2, payload= <<"34">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    %%{_Left, _Right} = A3,
    Result = A3,
    ?_assertEqual({[B2#packet{seg_seq = 5002, payload_size = 1, payload= <<"4">>},
                    B1#packet{seg_seq = 5000, payload_size = 2, payload= <<"12">>}],% Reverse overlap
                   []
                  }, Result).

acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_6() ->
    ForwardOverlapStrategy = favour_new_data_for_forward_overlap,
    B1 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    B2 = #packet{seg_seq = 5001, payload_size = 1, payload= <<"4">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    %%{_Left, _Right} = A3,
    Result = A3,
    ?_assertEqual({[B1#packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>}],
                   []
                  }, Result).

acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_7() ->
    ForwardOverlapStrategy = favour_new_data_for_forward_overlap,
    B1 = #packet{seg_seq = 5001, payload_size = 1, payload= <<"4">>},
    B2 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    %%{_Left, _Right} = A3,
    Result = A3,
    ?_assertEqual({[B2#packet{seg_seq = 5002, payload_size = 1, payload= <<"3">>},
                    B2#packet{seg_seq = 5001, payload_size = 1, payload= <<"2">>},
                    B2#packet{seg_seq = 5000, payload_size = 1, payload= <<"1">>}],
                   []
                  }, Result).


acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_8() ->
    ForwardOverlapStrategy = favour_new_data_for_forward_overlap,
    B1 = #packet{seg_seq = 5000, payload_size = 1, payload= <<"4">>},
    B2 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    %%{_Left, _Right} = A3,
    Result = A3,
    ?_assertEqual({[B2#packet{seg_seq = 5001, payload_size = 2, payload= <<"23">>},
                    B1],
                   []
                  }, Result).

acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_9() ->
    ForwardOverlapStrategy = favour_new_data_for_forward_overlap,
    B1 = #packet{seg_seq = 5002, payload_size = 1, payload= <<"4">>},
    B2 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    %%{_Left, _Right} = A3,
    Result = A3,
    ?_assertEqual({[B1#packet{seg_seq = 5002, payload_size = 1, payload= <<"3">>},
                    B2#packet{seg_seq = 5000, payload_size = 2, payload= <<"12">>}],
                   []
                  }, Result).

acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_10() ->
    ForwardOverlapStrategy = favour_new_data_for_forward_overlap,
    B1 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    B2 = #packet{seg_seq = 5000, payload_size = 1, payload= <<"4">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    %%{_Left, _Right} = A3,
    Result = A3,
    ?_assertEqual({[B1],
                   []
                  }, Result).

acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_11() ->
    ForwardOverlapStrategy = favour_new_data_for_forward_overlap,
    B1 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    B2 = #packet{seg_seq = 5001, payload_size = 1, payload= <<"4">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    %%{_Left, _Right} = A3,
    Result = A3,
    ?_assertEqual({[B1],
                   []
                  }, Result).

acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_12() ->
    ForwardOverlapStrategy = favour_new_data_for_forward_overlap,
    B1 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    B2 = #packet{seg_seq = 5002, payload_size = 1, payload= <<"4">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    %%{_Left, _Right} = A3,
    Result = A3,
    ?_assertEqual({[B1],
                   []
                  }, Result).

acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_13() ->
    ForwardOverlapStrategy = favour_new_data_for_forward_overlap,
    B1 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    B2 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"456">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    %%{_Left, _Right} = A3,
    Result = A3,
    ?_assertEqual({[B1],
                   []
                  }, Result).

acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_14() ->
    ForwardOverlapStrategy = favour_new_data_for_forward_overlap,
    B1 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    B2 = #packet{seg_seq = 5001, payload_size = 3, payload= <<"456">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    %%{_Left, _Right} = A3,
    Result = A3,
    ?_assertEqual({[B2#packet{seg_seq = 5003, payload_size = 1, payload= <<"6">>},
                    B1],
                   []
                  }, Result).

acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_15() ->
    ForwardOverlapStrategy = favour_new_data_for_forward_overlap,
    B1 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    B2 = #packet{seg_seq = 5002, payload_size = 3, payload= <<"456">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    %%{_Left, _Right} = A3,
    Result = A3,
    ?_assertEqual({[B2#packet{seg_seq = 5003, payload_size = 2, payload= <<"56">>},
                    B1],
                   []
                  }, Result).

acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_16() ->
    ForwardOverlapStrategy = favour_new_data_for_forward_overlap,
    B1 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    B2 = #packet{seg_seq = 5003, payload_size = 3, payload= <<"456">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    %%{_Left, _Right} = A3,
    Result = A3,
    ?_assertEqual({[B2#packet{seg_seq = 5003, payload_size = 3, payload= <<"456">>},
                    B1],
                   []
                  }, Result).

acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_17() ->
    ForwardOverlapStrategy = favour_new_data_for_forward_overlap,
    B1 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    B2 = #packet{seg_seq = 5004, payload_size = 3, payload= <<"456">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    %%{_Left, _Right} = A3,
    Result = A3,
    ?_assertEqual({[B2#packet{seg_seq = 5004, payload_size = 3, payload= <<"456">>},
                    B1],
                   []
                  }, Result).

acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_18() ->
    ForwardOverlapStrategy = favour_new_data_for_forward_overlap,
    B1 = #packet{seg_seq = 5001, payload_size = 3, payload= <<"123">>},
    B2 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"456">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    %%{_Left, _Right} = A3,
    Result = A3,
    ?_assertEqual({[B2#packet{seg_seq = 5003, payload_size = 1, payload= <<"3">>},
                    B1#packet{seg_seq = 5001, payload_size = 2, payload= <<"56">>}, 
                    B1#packet{seg_seq = 5000, payload_size = 1, payload= <<"4">>}],
                   []
                  }, Result).

acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_19() ->
    ForwardOverlapStrategy = favour_new_data_for_forward_overlap,
    B1 = #packet{seg_seq = 5002, payload_size = 3, payload= <<"123">>},
    B2 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"456">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    %%{_Left, _Right} = A3,
    Result = A3,
    ?_assertEqual({[B2#packet{seg_seq = 5003, payload_size = 2, payload= <<"23">>},
                    B1#packet{seg_seq = 5002, payload_size = 1, payload= <<"6">>},
                    B1#packet{seg_seq = 5000, payload_size = 2, payload= <<"45">>}],
                   []
                  }, Result).

acknowledgePayloadReceptionBuffer_favour_new_data_for_forward_overlap_20() ->
    ForwardOverlapStrategy = favour_new_data_for_forward_overlap,
    B1 = #packet{seg_seq = 5003, payload_size = 3, payload= <<"123">>},
    B2 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"456">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    %%{_Left, _Right} = A3,
    Result = A3,
    ?_assertEqual({[B1#packet{seg_seq = 5000, payload_size = 3, payload= <<"456">>}],
                   [B2#packet{seg_seq = 5003, payload_size = 3, payload= <<"123">>}]
                  }, Result).


acknowledgePayloadReceptionBuffer_always_favour_old_data_1() ->
    ForwardOverlapStrategy = always_favour_old_data,
    B1 = #packet{seg_seq = 5000, payload_size = 1, payload= <<"A">>},
    B2 = #packet{seg_seq = 5001, payload_size = 1, payload= <<"T">>},
    B3 = #packet{seg_seq = 5002, payload_size = 1, payload= <<"T">>},
    B4 = #packet{seg_seq = 5003, payload_size = 1, payload= <<"A">>},
    B5 = #packet{seg_seq = 5005, payload_size = 1, payload= <<"K">>},
    B6 = #packet{seg_seq = 5004, payload_size = 2, payload= <<"CH">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    A4 = stream_lib:insert(B3, A3, ForwardOverlapStrategy),
    A5 = stream_lib:insert(B4, A4, ForwardOverlapStrategy),
    A6 = stream_lib:insert(B5, A5, ForwardOverlapStrategy),
    A7 = stream_lib:insert(B6, A6, ForwardOverlapStrategy),
    %%{_Left, _Right} = A7,
    Result = A7,
    ?_assertEqual({[B6#packet{seg_seq = 5005, payload_size = 1, payload= <<"K">>}, B5#packet{seg_seq = 5004, payload_size = 1, payload= <<"C">>}, B4, B3, B2, B1],
                   []
                  }, Result).

acknowledgePayloadReceptionBuffer_always_favour_old_data_2() ->
    ForwardOverlapStrategy = always_favour_old_data,
    B1 = #packet{seg_seq = 5000, payload_size = 1, payload= <<"A">>},
    B2 = #packet{seg_seq = 5001, payload_size = 1, payload= <<"T">>},
    B3 = #packet{seg_seq = 5002, payload_size = 1, payload= <<"T">>},
    B4 = #packet{seg_seq = 5003, payload_size = 1, payload= <<"A">>},
    B5 = #packet{seg_seq = 5005, payload_size = 1, payload= <<"K">>},
    B6 = #packet{seg_seq = 5003, payload_size = 2, payload= <<"IC">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    A4 = stream_lib:insert(B3, A3, ForwardOverlapStrategy),
    A5 = stream_lib:insert(B4, A4, ForwardOverlapStrategy),
    A6 = stream_lib:insert(B5, A5, ForwardOverlapStrategy),
    A7 = stream_lib:insert(B6, A6, ForwardOverlapStrategy),
    {_Left, _Right} = A7,
    Result = A7,
    ?_assertEqual({[B5#packet{seg_seq = 5004, payload_size = 1, payload= <<"C">>}, B4, B3, B2, B1],
                   [B6#packet{seg_seq = 5005, payload_size = 1, payload= <<"K">>}]
                  }, Result).

acknowledgePayloadReceptionBuffer_always_favour_old_data_3() ->
    ForwardOverlapStrategy = always_favour_old_data,
    B1 = #packet{seg_seq = 5000, payload_size = 1, payload= <<"A">>},
    B2 = #packet{seg_seq = 5001, payload_size = 1, payload= <<"T">>},
    B3 = #packet{seg_seq = 5002, payload_size = 1, payload= <<"T">>},
    B4 = #packet{seg_seq = 5003, payload_size = 1, payload= <<"A">>},
    B5 = #packet{seg_seq = 5005, payload_size = 1, payload= <<"K">>},
    B6 = #packet{seg_seq = 5003, payload_size = 3, payload= <<"ICX">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    A4 = stream_lib:insert(B3, A3, ForwardOverlapStrategy),
    A5 = stream_lib:insert(B4, A4, ForwardOverlapStrategy),
    A6 = stream_lib:insert(B5, A5, ForwardOverlapStrategy),
    A7 = stream_lib:insert(B6, A6, ForwardOverlapStrategy),
    %%{_Left, _Right} = A7,
    Result = A7,
    ?_assertEqual({[B6#packet{seg_seq = 5005, payload_size = 1, payload= <<"K">>},
                    B5#packet{seg_seq = 5004, payload_size = 1, payload= <<"C">>}, B4, B3, B2, B1],
                   []
                  }, Result).

acknowledgePayloadReceptionBuffer_always_favour_old_data_4() ->
    ForwardOverlapStrategy = always_favour_old_data,
    B1 = #packet{seg_seq = 5000, payload_size = 1, payload= <<"A">>},
    B2 = #packet{seg_seq = 5001, payload_size = 1, payload= <<"T">>},
    B3 = #packet{seg_seq = 5002, payload_size = 1, payload= <<"T">>},
    B4 = #packet{seg_seq = 5003, payload_size = 1, payload= <<"A">>},
    B5 = #packet{seg_seq = 5005, payload_size = 1, payload= <<"K">>},
    B6 = #packet{seg_seq = 5003, payload_size = 4, payload= <<"ICXY">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    A4 = stream_lib:insert(B3, A3, ForwardOverlapStrategy),
    A5 = stream_lib:insert(B4, A4, ForwardOverlapStrategy),
    A6 = stream_lib:insert(B5, A5, ForwardOverlapStrategy),
    A7 = stream_lib:insert(B6, A6, ForwardOverlapStrategy),
    %%{_Left, _Right} = A7,
    Result = A7,
    ?_assertEqual({[B6#packet{seg_seq = 5006, payload_size = 1, payload= <<"Y">>},
                    B6#packet{seg_seq = 5005, payload_size = 1, payload= <<"K">>},
                    B5#packet{seg_seq = 5004, payload_size = 1, payload= <<"C">>}, B4, B3, B2, B1],
                   []
                  }, Result).


acknowledgePayloadReceptionBuffer_always_favour_old_data_5() ->
    ForwardOverlapStrategy = always_favour_old_data,
    B1 = #packet{seg_seq = 5000, payload_size = 2, payload= <<"12">>},
    B2 = #packet{seg_seq = 5001, payload_size = 2, payload= <<"34">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    %%{_Left, _Right} = A3,
    Result = A3,
    ?_assertEqual({[B2#packet{seg_seq = 5002, payload_size = 1, payload= <<"4">>},
                    B1#packet{seg_seq = 5000, payload_size = 2, payload= <<"12">>}],
                   []
                  }, Result).

acknowledgePayloadReceptionBuffer_always_favour_old_data_6() ->
    ForwardOverlapStrategy = always_favour_old_data,
    B1 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    B2 = #packet{seg_seq = 5001, payload_size = 1, payload= <<"4">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    %%{_Left, _Right} = A3,
    Result = A3,
    ?_assertEqual({[B1#packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>}],
                   []
                  }, Result).

acknowledgePayloadReceptionBuffer_always_favour_old_data_7() ->
    ForwardOverlapStrategy = always_favour_old_data,
    B1 = #packet{seg_seq = 5001, payload_size = 1, payload= <<"4">>},
    B2 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    %%{_Left, _Right} = A3,
    Result = A3,
    ?_assertEqual({[B2#packet{seg_seq = 5002, payload_size = 1, payload= <<"3">>},
                    B1,
                    B2#packet{seg_seq = 5000, payload_size = 1, payload= <<"1">>}],
                   []
                  }, Result).

acknowledgePayloadReceptionBuffer_always_favour_old_data_8() ->
    ForwardOverlapStrategy = always_favour_old_data,
    B1 = #packet{seg_seq = 5000, payload_size = 1, payload= <<"4">>},
    B2 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    %%{_Left, _Right} = A3,
    Result = A3,
    ?_assertEqual({[B2#packet{seg_seq = 5001, payload_size = 2, payload= <<"23">>},
                    B1],
                   []
                  }, Result).

acknowledgePayloadReceptionBuffer_always_favour_old_data_9() ->
    ForwardOverlapStrategy = always_favour_old_data,
    B1 = #packet{seg_seq = 5002, payload_size = 1, payload= <<"4">>},
    B2 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    %%{_Left, _Right} = A3,
    Result = A3,
    ?_assertEqual({[B1, 
                    B2#packet{seg_seq = 5000, payload_size = 2, payload= <<"12">>}],
                   []
                  }, Result).

acknowledgePayloadReceptionBuffer_always_favour_old_data_10() ->
    ForwardOverlapStrategy = always_favour_old_data,
    B1 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    B2 = #packet{seg_seq = 5000, payload_size = 1, payload= <<"4">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    %%{_Left, _Right} = A3,
    Result = A3,
    ?_assertEqual({[B1],
                   []
                  }, Result).

acknowledgePayloadReceptionBuffer_always_favour_old_data_11() ->
    ForwardOverlapStrategy = always_favour_old_data,
    B1 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    B2 = #packet{seg_seq = 5001, payload_size = 1, payload= <<"4">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    %%{_Left, _Right} = A3,
    Result = A3,
    ?_assertEqual({[B1],
                   []
                  }, Result).

acknowledgePayloadReceptionBuffer_always_favour_old_data_12() ->
    ForwardOverlapStrategy = always_favour_old_data,
    B1 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    B2 = #packet{seg_seq = 5002, payload_size = 1, payload= <<"4">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    %%{_Left, _Right} = A3,
    Result = A3,
    ?_assertEqual({[B1],
                   []
                  }, Result).

acknowledgePayloadReceptionBuffer_always_favour_old_data_13() ->
    ForwardOverlapStrategy = always_favour_old_data,
    B1 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    B2 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"456">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    %%{_Left, _Right} = A3,
    Result = A3,
    ?_assertEqual({[B1],
                   []
                  }, Result).

acknowledgePayloadReceptionBuffer_always_favour_old_data_14() ->
    ForwardOverlapStrategy = always_favour_old_data,
    B1 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    B2 = #packet{seg_seq = 5001, payload_size = 3, payload= <<"456">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    %%{_Left, _Right} = A3,
    Result = A3,
    ?_assertEqual({[B2#packet{seg_seq = 5003, payload_size = 1, payload= <<"6">>},
                    B1],
                   []
                  }, Result).

acknowledgePayloadReceptionBuffer_always_favour_old_data_15() ->
    ForwardOverlapStrategy = always_favour_old_data,
    B1 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    B2 = #packet{seg_seq = 5002, payload_size = 3, payload= <<"456">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    %%{_Left, _Right} = A3,
    Result = A3,
    ?_assertEqual({[B2#packet{seg_seq = 5003, payload_size = 2, payload= <<"56">>},
                    B1],
                   []
                  }, Result).

acknowledgePayloadReceptionBuffer_always_favour_old_data_16() ->
    ForwardOverlapStrategy = always_favour_old_data,
    B1 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    B2 = #packet{seg_seq = 5003, payload_size = 3, payload= <<"456">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    %%{_Left, _Right} = A3,
    Result = A3,
    ?_assertEqual({[B2#packet{seg_seq = 5003, payload_size = 3, payload= <<"456">>},
                    B1],
                   []
                  }, Result).

acknowledgePayloadReceptionBuffer_always_favour_old_data_17() ->
    ForwardOverlapStrategy = always_favour_old_data,
    B1 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    B2 = #packet{seg_seq = 5004, payload_size = 3, payload= <<"456">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    %%{_Left, _Right} = A3,
    Result = A3,
    ?_assertEqual({[B2#packet{seg_seq = 5004, payload_size = 3, payload= <<"456">>},
                    B1],
                   []
                  }, Result).

acknowledgePayloadReceptionBuffer_always_favour_old_data_18() ->
    ForwardOverlapStrategy = always_favour_old_data,
    B1 = #packet{seg_seq = 5001, payload_size = 3, payload= <<"123">>},
    B2 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"456">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    %%{_Left, _Right} = A3,
    Result = A3,
    ?_assertEqual({[B2#packet{seg_seq = 5001, payload_size = 3, payload= <<"123">>},
                    B1#packet{seg_seq = 5000, payload_size = 1, payload= <<"4">>}],
                   []
                  }, Result).

acknowledgePayloadReceptionBuffer_always_favour_old_data_19() ->
    ForwardOverlapStrategy = always_favour_old_data,
    B1 = #packet{seg_seq = 5002, payload_size = 3, payload= <<"123">>},
    B2 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"456">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    %%{_Left, _Right} = A3,
    Result = A3,
    ?_assertEqual({[B2#packet{seg_seq = 5002, payload_size = 3, payload= <<"123">>},
                    B1#packet{seg_seq = 5000, payload_size = 2, payload= <<"45">>}],
                   []
                  }, Result).

acknowledgePayloadReceptionBuffer_always_favour_old_data_20() ->
    ForwardOverlapStrategy = always_favour_old_data,
    B1 = #packet{seg_seq = 5003, payload_size = 3, payload= <<"123">>},
    B2 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"456">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, ForwardOverlapStrategy),
    A3 = stream_lib:insert(B2, A2, ForwardOverlapStrategy),
    %%{_Left, _Right} = A3,
    Result = A3,
    ?_assertEqual({[B1#packet{seg_seq = 5000, payload_size = 3, payload= <<"456">>}],
                   [B2#packet{seg_seq = 5003, payload_size = 3, payload= <<"123">>}]
                  }, Result).


checkSAckReceptionBuffer_favour_new_data_for_forward_overlap_1() -> 
    Direction = initiator,
    SEG_ACK = 5006,
    Overlapping_payload_strategy = favour_new_data_for_forward_overlap,
    Sack_store =
	%% {SEG_SEQ, Retransmission_Index, Payload_size, Payload}
	[{5000, 1, 1, <<"A">>}, 
	 {5001, 1, 1, <<"T">>},
	 {5002, 1, 1, <<"T">>},
	 {5003, 1, 1, <<"A">>},
	 {5005, 1, 1, <<"K">>},
	 {5004, 2, 2, <<"CH">>}],
    Ack_payload_store = <<>>,
    RCV_NXT = 5000,
    Window = 100,
    ?_assertEqual({ok, [], <<"ATTACH">>, 5006}, stream_worker:checkSAckReceptionBuffer(Direction, SEG_ACK, _Acc = [], run, Overlapping_payload_strategy, 
										       Sack_store, Ack_payload_store, RCV_NXT, Window)).

checkSAckReceptionBuffer_favour_new_data_for_forward_overlap_2() -> 
    Direction = initiator,
    SEG_ACK = 5006,
    Overlapping_payload_strategy = favour_new_data_for_forward_overlap,
    Sack_store =
	%% {SEG_SEQ, Retransmission_Index, Payload_size, Payload}
	[{5000, 1, 1, <<"A">>}, 
	 {5001, 1, 1, <<"T">>},
	 {5002, 1, 1, <<"T">>},
	 {5003, 1, 1, <<"A">>},
	 {5003, 2, 2, <<"IC">>},
	 {5005, 2, 1, <<"K">>}],
    Ack_payload_store = <<>>,
    RCV_NXT = 5000,
    Window = 100,
    ?_assertEqual({ok, [], <<"ATTACK">>, 5006}, stream_worker:checkSAckReceptionBuffer(Direction, SEG_ACK, _Acc = [], run, Overlapping_payload_strategy, 
										       Sack_store, Ack_payload_store, RCV_NXT, Window)).


checkSAckReceptionBuffer_favour_new_data_for_forward_overlap_3() -> 
    Direction = initiator,
    SEG_ACK = 5006,
    Overlapping_payload_strategy = favour_new_data_for_forward_overlap,
    Sack_store =
	%% {SEG_SEQ, Retransmission_Index, Payload_size, Payload}
	[{5000, 1, 1, <<"A">>}, 
	 {5001, 1, 1, <<"T">>},
	 {5002, 1, 1, <<"T">>},
	 {5003, 1, 1, <<"A">>},
	 {5005, 1, 1, <<"K">>},
	 {5003, 2, 3, <<"ICX">>}],
    Ack_payload_store = <<>>,
    RCV_NXT = 5000,
    Window = 100,
    ?_assertEqual({ok, [], <<"ATTACX">>, 5006}, stream_worker:checkSAckReceptionBuffer(Direction, SEG_ACK, _Acc = [], run, Overlapping_payload_strategy, 
										       Sack_store, Ack_payload_store, RCV_NXT, Window)).
get_first_element_1() ->
    A1 = stream_lib:new(),
    Result = stream_lib:get_first_element(A1),
    ?_assertEqual({empty, A1}, Result). 

get_first_element_2() ->
    Overlapping_payload_strategy = favour_new_data_for_forward_overlap,
    B1 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, Overlapping_payload_strategy),
    Result = stream_lib:get_first_element(A2),
    ?_assertEqual({{value, B1}, {[], []}}, Result).

get_first_element_3() ->
    Overlapping_payload_strategy = favour_new_data_for_forward_overlap,
    B1 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    B2 = #packet{seg_seq = 5003, payload_size = 3, payload= <<"456">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, Overlapping_payload_strategy),
    A3 = stream_lib:insert(B2, A2, Overlapping_payload_strategy),
    Result = stream_lib:get_first_element(A3),
    ?_assertEqual({{value, B1}, {[B2], []}}, Result).

get_first_element_4() ->
    Overlapping_payload_strategy = favour_new_data_for_forward_overlap,
    B1 = #packet{seg_seq = 5003, payload_size = 3, payload= <<"456">>},
    B2 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, Overlapping_payload_strategy),
    A3 = stream_lib:insert(B2, A2, Overlapping_payload_strategy),
    Result = stream_lib:get_first_element(A3),
    ?_assertEqual({{value, B2}, {[], [B1]}}, Result).

get_first_element_5() ->
    Overlapping_payload_strategy = favour_new_data_for_forward_overlap,
    B1 = #packet{seg_seq = 5003, payload_size = 3, payload= <<"456">>},
    B2 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    B3 = #packet{seg_seq = 5006, payload_size = 3, payload= <<"789">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, Overlapping_payload_strategy),
    A3 = stream_lib:insert(B2, A2, Overlapping_payload_strategy),
    A4 = stream_lib:insert(B3, A3, Overlapping_payload_strategy),
    Result = stream_lib:get_first_element(A4),
    ?_assertEqual({{value, B2}, {[B3, B1], []}}, Result).

get_first_element_6() ->
    B1 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    A1 = {[], [B1]},
    Result = stream_lib:get_first_element(A1),
    ?_assertEqual({{value, B1}, {[], []}}, Result).

get_first_element_7() ->
    B1 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    B2 = #packet{seg_seq = 5003, payload_size = 3, payload= <<"456">>},
    A1 = {[], [B2, B1]},
    Result = stream_lib:get_first_element(A1),
    ?_assertEqual({{value, B1}, {[], [B2]}}, Result).

get_first_element_8() ->
    B1 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    B2 = #packet{seg_seq = 5003, payload_size = 3, payload= <<"456">>},
    B3 = #packet{seg_seq = 5006, payload_size = 3, payload= <<"789">>},
    A1 = {[B2,B1], [B3]},
    Result = stream_lib:get_first_element(A1),
    ?_assertEqual({{value, B1}, {[B2], [B3]}}, Result).


get_first_element_SEG_ACK_RCV_NXT_1() ->
    A1 = stream_lib:new(),
    Result = stream_lib:get_first_element(A1, 5000, 5000),
    ?_assertEqual({empty, A1}, Result). 

get_first_element_SEG_ACK_RCV_NXT_2()->
    Overlapping_payload_strategy = favour_new_data_for_forward_overlap,
    B1 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    B2 = #packet{seg_seq = 5003, payload_size = 3, payload= <<"456">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, Overlapping_payload_strategy),
    A3 = stream_lib:insert(B2, A2, Overlapping_payload_strategy),
    Result = stream_lib:get_first_element(A3, 5000, 5000),
    ?_assertEqual({keep_buffer, A3}, Result).

get_first_element_SEG_ACK_RCV_NXT_3()->
    Overlapping_payload_strategy = favour_new_data_for_forward_overlap,
    B1 = #packet{seg_seq = 5003, payload_size = 3, payload= <<"456">>},
    B2 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, Overlapping_payload_strategy),
    A3 = stream_lib:insert(B2, A2, Overlapping_payload_strategy),
    B2x = #packet{seg_seq = 5001, payload_size = 2, payload= <<"23">>},
    A3x = stream_lib:insert(B2x, A2, Overlapping_payload_strategy),

    Result = stream_lib:get_first_element(A3, 5001, 5001),
    ?_assertEqual({{lastInSEG_ACK,  #packet{seg_seq = 5000, payload_size = 1, payload= <<"1">>}}, A3x}, Result).

get_first_element_SEG_ACK_RCV_NXT_4()->
    Overlapping_payload_strategy = favour_new_data_for_forward_overlap,
    B1 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    B2 = #packet{seg_seq = 5003, payload_size = 3, payload= <<"456">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, Overlapping_payload_strategy),
    A3 = stream_lib:insert(B2, A2, Overlapping_payload_strategy),
    Result = stream_lib:get_first_element(A3, 5004, 5004),
    ?_assertEqual({{value, B1}, {[B2], []}}, Result).

get_first_element_SEG_ACK_RCV_NXT_5()->
    Overlapping_payload_strategy = favour_new_data_for_forward_overlap,
    B1 = #packet{seg_seq = 5003, payload_size = 3, payload= <<"456">>},
    B2 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, Overlapping_payload_strategy),
    A3 = stream_lib:insert(B2, A2, Overlapping_payload_strategy),
    B2x = #packet{seg_seq = 5002, payload_size = 1, payload= <<"3">>},
    A3x = stream_lib:insert(B2x, A2, Overlapping_payload_strategy),

    Result = stream_lib:get_first_element(A3, 5002, 5001),
    ?_assertEqual({{lastInSEG_ACK, #packet{seg_seq = 5000, payload_size = 2, payload= <<"12">>}}, A3x}, Result).

get_first_element_SEG_ACK_RCV_NXT_6()->
    Overlapping_payload_strategy = favour_new_data_for_forward_overlap,
    B1 = #packet{seg_seq = 5003, payload_size = 3, payload= <<"456">>},
    B2 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, Overlapping_payload_strategy),
    A3 = stream_lib:insert(B2, A2, Overlapping_payload_strategy),
    Result = stream_lib:get_first_element(A3, 5003, 5000),
    ?_assertEqual({{value, B2}, {[], [B1]}}, Result).

get_first_element_SEG_ACK_RCV_NXT_7()->
    Overlapping_payload_strategy = favour_new_data_for_forward_overlap,
    B1 = #packet{seg_seq = 5003, payload_size = 3, payload= <<"456">>},
    B2 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, Overlapping_payload_strategy),
    A3 = stream_lib:insert(B2, A2, Overlapping_payload_strategy),
    Result = stream_lib:get_first_element(A3, 5004, 5000),
    ?_assertEqual({{value, B2}, {[], [B1]}}, Result).

get_first_element_SEG_ACK_RCV_NXT_8()->
    Overlapping_payload_strategy = favour_new_data_for_forward_overlap,
    B1 = #packet{seg_seq = 5003, payload_size = 3, payload= <<"456">>},
    B2 = #packet{seg_seq = 5000, payload_size = 3, payload= <<"123">>},
    A1 = stream_lib:new(),
    A2 = stream_lib:insert(B1, A1, Overlapping_payload_strategy),
    A3 = stream_lib:insert(B2, A2, Overlapping_payload_strategy),
    Result = stream_lib:get_first_element(A3, 5004, 5001),
    ?_assertEqual({{value, B2}, {[], [B1]}}, Result).

