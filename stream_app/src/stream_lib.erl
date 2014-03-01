-module(stream_lib).
-export([new/0, compare_32/2, get_first_element/1, get_first_element/3, insert/3]).
-include("../include/stream_lib.hrl").

%%-define(Xseq_HLeft_seq(Comperator), (X#packet.seg_seq Comperator HLeft#packet.seg_seq)).
%%-define(Xseq_HLeft_seq_plus_payload(Comperator), (X#packet.seg_seq Comperator HLeft#packet.seg_seq + HLeft#packet.payload_size)).
%%-define(Xseq_plus_payload_HLeft_seq_plus_payload(Comperator), (X#packet.seg_seq + X#packet.payload_size Comperator HLeft#packet.seg_seq + HLeft#packet.payload_size)).

%%-define(HRight_Xseq(Comperator), (HRight#packet.seg_seq Comperator X#packet.seg_seq)).
%%-define(HRight_Xseq_plus_payload(Comperator), (HRight#packet.seg_seq Comperator X#packet.seg_seq + X#packet.payload_size)).
%%-define(HRight_plus_payload_Xseq_plus_payload(Comperator), (HRight#packet.seg_seq + HLeft#packet.payload_size Comperator X#packet.seg_seq + X#packet.payload_size)).

-define(Xseq_HLeft_seq(Comperator), (CompL#compl.xseq_hleft_seq == Comperator)).
-define(Xseq_HLeft_seq_plus_payload(Comperator), (CompL#compl.xseq_hleft_seq_plus_payload == Comperator)).
-define(Xseq_plus_payload_HLeft_seq_plus_payload(Comperator), (CompL#compl.xseq_plus_payload_hleft_seq_plus_payload == Comperator)).

-define(HRight_Xseq(Comperator), (CompR#compr.hright_xseq == Comperator)).
-define(HRight_Xseq_plus_payload(Comperator), (CompR#compr.hright_xseq_plus_payload == Comperator)).
-define(HRight_plus_payload_Xseq_plus_payload(Comperator), (CompR#compr.hright_plus_payload_xseq_plus_payload =:= Comperator)).

-record(compl, {
          xseq_hleft_seq::atom(),
          xseq_hleft_seq_plus_payload::atom(),
          xseq_plus_payload_hleft_seq_plus_payload::atom()
	 }).

-record(compr, {
          hright_xseq::atom(),
          hright_xseq_plus_payload::atom(),
          hright_plus_payload_xseq_plus_payload::atom()
	 }).

calclualte_comp([], [], _X) -> 
    CompL = #compl{xseq_hleft_seq                         = undefined,
		   xseq_hleft_seq_plus_payload              = undefined,
		   xseq_plus_payload_hleft_seq_plus_payload = undefined},
    CompR = #compr{hright_xseq                            = undefined,
		   hright_xseq_plus_payload                 = undefined,
		   hright_plus_payload_xseq_plus_payload    = undefined},
    {CompL, CompR};

calclualte_comp([], [HRight|_TRight], X) ->
    CompL = #compl{xseq_hleft_seq                         = undefined,
		   xseq_hleft_seq_plus_payload              = undefined,
		   xseq_plus_payload_hleft_seq_plus_payload = undefined},
    CompR = #compr{hright_xseq                            = compare_32(HRight#packet.seg_seq, X#packet.seg_seq),
		   hright_xseq_plus_payload                 = compare_32(HRight#packet.seg_seq, X#packet.seg_seq + X#packet.payload_size),
		   hright_plus_payload_xseq_plus_payload    = compare_32(HRight#packet.seg_seq + HRight#packet.payload_size, X#packet.seg_seq + X#packet.payload_size)},
    {CompL, CompR};

calclualte_comp([HLeft|_TLeft], [], X) ->
    CompL = #compl{
	       xseq_hleft_seq                           = compare_32(X#packet.seg_seq, HLeft#packet.seg_seq),
	       xseq_hleft_seq_plus_payload              = compare_32(X#packet.seg_seq, HLeft#packet.seg_seq + HLeft#packet.payload_size),
	       xseq_plus_payload_hleft_seq_plus_payload = compare_32(X#packet.seg_seq + X#packet.payload_size, HLeft#packet.seg_seq + HLeft#packet.payload_size)},
    CompR = #compr{hright_xseq                            = undefined,
		   hright_xseq_plus_payload                 = undefined,
		   hright_plus_payload_xseq_plus_payload    = undefined},
    {CompL, CompR};

calclualte_comp([HLeft|_TLeft], [HRight|_TRight], X) ->
    CompL = #compl{
	       xseq_hleft_seq                           = compare_32(X#packet.seg_seq, HLeft#packet.seg_seq),
	       xseq_hleft_seq_plus_payload              = compare_32(X#packet.seg_seq, HLeft#packet.seg_seq + HLeft#packet.payload_size),
	       xseq_plus_payload_hleft_seq_plus_payload = compare_32(X#packet.seg_seq + X#packet.payload_size, HLeft#packet.seg_seq + HLeft#packet.payload_size)},
    CompR = #compr{
	       hright_xseq                              = compare_32(HRight#packet.seg_seq, X#packet.seg_seq),
	       hright_xseq_plus_payload                 = compare_32(HRight#packet.seg_seq, X#packet.seg_seq + X#packet.payload_size),
	       hright_plus_payload_xseq_plus_payload    = compare_32(HRight#packet.seg_seq + HRight#packet.payload_size, X#packet.seg_seq + X#packet.payload_size)},
    {CompL, CompR}.


%% warning sequence number needs to be mod 32

new() -> {[], []}.

get_first_element(Queue, SEG_ACK, RCV_NXT)->
    SEG_ACK32 = modulo32bit(SEG_ACK),
    RCV_NXT32 = modulo32bit(RCV_NXT),
    case get_first_element(Queue) of
	{empty, QueueNew} -> 
	    {empty, QueueNew};
	{{value, Packet}, QueueNew} -> 
	    case compare_32(SEG_ACK32, Packet#packet.seg_seq)  of 
		'<' -> %  SEG_ACK32 < Packet#packet.seg_seq
                    {keep_buffer, Queue};
		'==' -> %  SEG_ACK32 == Packet#packet.seg_seq
                    {keep_buffer, Queue};
		_Other0 -> %  undef or (SEG_ACK32 >= Packet#packet.seg_seq)
                    case compare_32(RCV_NXT32, Packet#packet.seg_seq) of
			'<' -> % RCV_NXT32 > Packet#packet.seg_seq
                       	    {keep_buffer, Queue};
			_Other1 -> %  undef or (RCV_NXT32 <= Packet#packet.seg_seq)
			    case  compare_32(SEG_ACK32, Packet#packet.seg_seq + Packet#packet.payload_size) of 
				'>' ->
				    {{value, Packet}, QueueNew};                    
				'==' ->
				    {{value, Packet}, QueueNew}; 
				_Other2 -> % undef or (SEG_ACK32 =< Packet#packet.seg_seq + Packet#packet.payload_size)
				    AcknowledgedPartSize = modulo32bit(SEG_ACK32 - Packet#packet.seg_seq),
				    Packetpayload = Packet#packet.payload,
				    %%lager:debug("AcknowledgedPartSize: ~p~n",[AcknowledgedPartSize]),
				    <<AcknowledgedPartPayload:AcknowledgedPartSize/binary, Rest/binary>> = <<Packetpayload/binary>>,
				    AcknowledgedPartNew = Packet#packet{payload_size = AcknowledgedPartSize, payload = <<AcknowledgedPartPayload/binary>>},
				    NotAcknowledgedPartNew = Packet#packet{seg_seq = modulo32bit(Packet#packet.seg_seq + AcknowledgedPartSize), payload_size = Packet#packet.payload_size-AcknowledgedPartSize, payload = <<Rest/binary>>},
				    {LeftNew, RightNew} = QueueNew,
				    QueueNew1 = insert(NotAcknowledgedPartNew, {LeftNew, RightNew},  _ForwardOverlapStrategy = always_favour_old_data, _OverlapNew = non_forward_overlap, calclualte_comp(LeftNew, RightNew, NotAcknowledgedPartNew)),
				    {{lastInSEG_ACK, AcknowledgedPartNew}, QueueNew1}
			    end

		    end
	    end
    end.                          

get_first_element({[], []}=Queue)->
    {empty, Queue};

get_first_element({Left, []})-> % Left non-empty, Right empty
    [HLeftReverse|TLeftReverse] = lists:reverse(Left),
    {{value, HLeftReverse}, {lists:reverse(TLeftReverse), []}};

get_first_element({[]=Left, Right})-> % Right non-empty
    [HRightReverse|TRightReverse] = lists:reverse(Right),
    {{value, HRightReverse}, {Left, lists:reverse(TRightReverse)}}; 

get_first_element({Left, Right})-> % Left non-empty, Right empty
    [HLeftReverse|TLeftReverse] = lists:reverse(Left),
    {{value, HLeftReverse}, {lists:reverse(TLeftReverse), Right}}.

insert(X, {Left, Right}, _ForwardOverlapStrategy) -> 
    LeftNew = Left,
    RightNew = Right,
    XNew = X,
    insert(XNew, {LeftNew, RightNew}, _ForwardOverlapStrategy, non_forward_overlap, calclualte_comp(LeftNew, RightNew, XNew)).

%% ignore empty packets

insert(X, {[]=Left, []=Right}, _ForwardOverlapStrategy, _Overlap, {_CompL, _CompR}) when
      X#packet.payload ==<<"">> -> 
       {Left, Right};
       
insert(X, {[]=Left, Right}, _ForwardOverlapStrategy, _Overlap, {_CompL, _CompR}) when
  X#packet.payload ==<<"">> -> 
       {Left, Right};
       
insert(X, {Left, []=Right}, _ForwardOverlapStrategy, _Overlap, {_CompL, _CompR}) when
  X#packet.payload ==<<"">> -> 
       {Left, Right};

insert(X, {Left, Right}, _ForwardOverlapStrategy, _Overlap, {_CompL, _CompR}) when
  X#packet.payload ==<<"">> -> 
       {Left, Right};

insert(X, {[], []}, _ForwardOverlapStrategy, _Overlap, {_CompL, _CompR}) -> 
    {[X], []};

%% Move left:

insert(X, {[]=_Left, [HRight|TRight]=_Right}, ForwardOverlapStrategy, Overlap, {_CompL, CompR}) when
      %%(HRight#packet.seg_seq =< X#packet.seg_seq) -> %% move left
      not(?HRight_Xseq('>')) ->
      LeftNew = [HRight],
      RightNew = TRight,
      XNew = X,
    insert(XNew, {LeftNew, RightNew}, ForwardOverlapStrategy, Overlap, calclualte_comp(LeftNew, RightNew, XNew));

%% Move right:

insert(X, {[HLeft|TLeft]=_Left, Right}, ForwardOverlapStrategy, Overlap, {CompL, _CompR}) when 
      %%(X#packet.seg_seq < HLeft#packet.seg_seq) -> %% move right
      ?Xseq_HLeft_seq('<') ->
      LeftNew = TLeft,
      RightNew = [HLeft|Right],
      XNew = X,
    insert(X, {LeftNew, RightNew}, ForwardOverlapStrategy, Overlap, calclualte_comp(LeftNew, RightNew, XNew));

%% Move left:

insert(X, {Left, [HRight|TRight]=_Right}, ForwardOverlapStrategy, Overlap, {_CompL, CompR}) when 
      %%(HRight#packet.seg_seq =< X#packet.seg_seq) -> %% move left
      not(?HRight_Xseq('>')) ->
      LeftNew = [HRight|Left],
      RightNew = TRight,
      XNew = X,
    insert(XNew, {LeftNew, RightNew}, ForwardOverlapStrategy, Overlap, calclualte_comp(LeftNew, RightNew, XNew));

%%Left empty, no overlapping with right:

insert(X, {[]= _Left, [_HRight|_TRight]=Right}, _ForwardOverlapStrategy, _Overlap, {_CompL, CompR}) when 
      %%(X#packet.seg_seq + X#packet.payload_size =< HRight#packet.seg_seq) -> 
      not(?HRight_Xseq_plus_payload('<')) ->
    {[X], Right};

%%Left empty, overlapping with right:

insert(X, {[]=_Left, [HRight|_TRight]=Right}, _ForwardOverlapStrategy, _Overlap, {_CompL, CompR}) when 
      %%(X#packet.seg_seq < HRight#packet.seg_seq) and
      %%(HRight#packet.seg_seq < X#packet.seg_seq + X#packet.payload_size) -> 
      ?HRight_Xseq('>'),
      ?HRight_Xseq_plus_payload('<') ->
    NonOverlappingSize = modulo32bit(HRight#packet.seg_seq - X#packet.seg_seq),
    Xpayload = X#packet.payload,
    <<NonOverlapppingPayload:NonOverlappingSize/binary, Rest/binary>> = <<Xpayload/binary>>,
      LeftNew = [X#packet{payload_size = NonOverlappingSize, payload = <<NonOverlapppingPayload/binary>>}],
      RightNew = Right,
      XNew = X#packet{seg_seq = X#packet.seg_seq+NonOverlappingSize, 
        payload_size = byte_size(Rest),
	payload = <<Rest/binary>>},
      insert(XNew, {LeftNew, RightNew}, _ForwardOverlapStrategy, _OverlapNew = forward_overlap, calclualte_comp(LeftNew, RightNew, XNew));

%% No overlapping with left:

insert(X, {[_HLeft|_TLeft]=Left, []}, _ForwardOverlapStrategy, _Overlap, {CompL, _CompR}) when 
      %%(HLeft#packet.seg_seq + HLeft#packet.payload_size =< X#packet.seg_seq) -> %% no overlapping area with left
      not(?Xseq_HLeft_seq_plus_payload('<'))->
    {[X|Left], []};

%% No overlapping with left and right:

insert(X, {[_HLeft|_TLeft]=Left, [_HRight|_TRight]=Right}, _ForwardOverlapStrategy, _Overlap, {CompL, CompR}) when 
      %%(HLeft#packet.seg_seq + HLeft#packet.payload_size =< X#packet.seg_seq) and
      %%(X#packet.seg_seq + X#packet.payload_size =< HRight#packet.seg_seq) -> %% no overlapping area with left
      not(?Xseq_HLeft_seq_plus_payload('<')),
      not(?HRight_Xseq_plus_payload('<')) ->
    {[X|Left], Right};

%% ReverseOverlap, full inclusion

insert(_X, {[_HLeft|_TLeft]=Left, Right}, always_favour_old_data = _ForwardOverlapStrategy, forward_overlap = _Overlap, {CompL, _CompR}) when 
      %%(HLeft#packet.seg_seq =< X#packet.seg_seq) and
      %%(X#packet.seg_seq < HLeft#packet.seg_seq + HLeft#packet.payload_size) and
      %%(X#packet.seg_seq + X#packet.payload_size =< HLeft#packet.seg_seq + HLeft#packet.payload_size) -> %% full overlapping area with left, thus replace old data
      not(?Xseq_HLeft_seq('<')), 
      ?Xseq_HLeft_seq_plus_payload('<'),
      not(?Xseq_plus_payload_HLeft_seq_plus_payload('>')) ->
    {Left, Right};

%% ReverseOverlap, full inclusion

insert(X, {[HLeft|TLeft]=Left, Right}, favour_new_data_for_forward_overlap = _ForwardOverlapStrategy, forward_overlap = _Overlap, {CompL, _CompR}) when 
      %%(HLeft#packet.seg_seq == X#packet.seg_seq) and
      %%(X#packet.seg_seq < HLeft#packet.seg_seq + HLeft#packet.payload_size) and
      %%(X#packet.seg_seq + X#packet.payload_size =< HLeft#packet.seg_seq + HLeft#packet.payload_size) -> %% full overlapping area with left, thus replace old data
      ?Xseq_HLeft_seq('=='),
      ?Xseq_HLeft_seq_plus_payload('<'),
      not(?Xseq_plus_payload_HLeft_seq_plus_payload('>'))  ->
      io:format("Left: ~p, Right: ~p, X:, ~p", [Left, Right, X]),
    OverlappingSize = X#packet.payload_size,
    HLeftpayload = HLeft#packet.payload,
    <<_OverlapppingPayload:OverlappingSize/binary, HLeftRest/binary>> = <<HLeftpayload/binary>>,
      LeftNew = [X|TLeft],
      RightNew = Right,
      XNew = HLeft#packet{seg_seq = X#packet.seg_seq+X#packet.payload_size, 
	payload_size = byte_size(<<HLeftRest/binary>>), 
	payload = <<HLeftRest/binary>>},
      insert(XNew, {LeftNew, RightNew}, _ForwardOverlapStrategy, _Overlap, calclualte_comp(LeftNew, RightNew, XNew));

%% ReverseOverlap, full inclusion

insert(_X, {[_HLeft|_TLeft]=Left, Right}, _ForwardOverlapStrategy, non_forward_overlap = _Overlap, {CompL, _CompR}) when 
      %%(HLeft#packet.seg_seq =< X#packet.seg_seq) and
      %%(X#packet.seg_seq < HLeft#packet.seg_seq + HLeft#packet.payload_size) and
      %%(X#packet.seg_seq + X#packet.payload_size =< HLeft#packet.seg_seq + HLeft#packet.payload_size) -> %% full overlapping area with left, thus replace old data
      not(?Xseq_HLeft_seq('<')),     
      ?Xseq_HLeft_seq_plus_payload('<'),
      not(?Xseq_plus_payload_HLeft_seq_plus_payload('>')) ->
    {Left, Right};

%% ReverseOverlap, full overlapping left

insert(X, {[HLeft|_TLeft]=Left, Right}, always_favour_old_data = ForwardOverlapStrategy, forward_overlap = _Overlap, {CompL, _CompR}) when 
      %%(HLeft#packet.seg_seq =< X#packet.seg_seq) and
      %%(X#packet.seg_seq < HLeft#packet.seg_seq + HLeft#packet.payload_size) and
      %%(HLeft#packet.seg_seq + HLeft#packet.payload_size =< X#packet.seg_seq + X#packet.payload_size) -> %% full overlapping area with left, thus replace old data
      not(?Xseq_HLeft_seq('<')),     
      ?Xseq_HLeft_seq_plus_payload('<'),      
      not(?Xseq_plus_payload_HLeft_seq_plus_payload('<')) ->      
    ReverseOverlapppingSize = modulo32bit(HLeft#packet.seg_seq + HLeft#packet.payload_size - X#packet.seg_seq),
    Xpayload = X#packet.payload,
    <<_ReverseOverlapppingPayload:ReverseOverlapppingSize/binary, Rest/binary>> = <<Xpayload/binary>>,
      LeftNew = Left,
      RightNew = Right,
      XNew = X#packet{seg_seq = X#packet.seg_seq + ReverseOverlapppingSize, 
		    payload_size = byte_size(<<Rest/binary>>), 
		    payload = <<Rest/binary>>},
    insert(XNew, {LeftNew, RightNew}, ForwardOverlapStrategy, _Overlap, calclualte_comp(LeftNew, RightNew, XNew));


%% ReverseOverlap, full overlapping left

insert(X, {[HLeft|TLeft]=_Left, Right}, favour_new_data_for_forward_overlap = ForwardOverlapStrategy, forward_overlap = _Overlap, {CompL, _CompR}) when 
      %%(HLeft#packet.seg_seq =< X#packet.seg_seq) and
      %%(X#packet.seg_seq < HLeft#packet.seg_seq + HLeft#packet.payload_size) and
      %%(HLeft#packet.seg_seq + HLeft#packet.payload_size =< X#packet.seg_seq + X#packet.payload_size) -> %% full overlapping area with left, thus replace old data
      not(?Xseq_HLeft_seq('<')),     
      ?Xseq_HLeft_seq_plus_payload('<'),        
      not(?Xseq_plus_payload_HLeft_seq_plus_payload('<')) ->          
    ReverseOverlapppingSize = modulo32bit(HLeft#packet.seg_seq + HLeft#packet.payload_size - X#packet.seg_seq),
    Xpayload = X#packet.payload,
    <<ReverseOverlapppingPayload:ReverseOverlapppingSize/binary, Rest/binary>> = <<Xpayload/binary>>,
      LeftNew = [X#packet{seg_seq = X#packet.seg_seq, 
		    payload_size = ReverseOverlapppingSize,
		    payload = <<ReverseOverlapppingPayload/binary>>}|TLeft],
      RightNew = Right,
      XNew = X#packet{seg_seq = X#packet.seg_seq + ReverseOverlapppingSize, 
		    payload_size = byte_size(<<Rest/binary>>), 
		    payload = <<Rest/binary>>},
    insert(XNew, {LeftNew, RightNew}, ForwardOverlapStrategy, _Overlap, calclualte_comp(LeftNew, RightNew, XNew));


%% ReverseOverlap, full overlapping left

insert(X, {[HLeft|_TLeft]=Left, Right}, ForwardOverlapStrategy, non_forward_overlap = _Overlap, {CompL, _CompR}) when 
      %%(HLeft#packet.seg_seq =< X#packet.seg_seq) and
      %%(X#packet.seg_seq < HLeft#packet.seg_seq + HLeft#packet.payload_size) and
      %%(HLeft#packet.seg_seq + HLeft#packet.payload_size =< X#packet.seg_seq + X#packet.payload_size) -> %% full overlapping area with left, thus replace old data
      not(?Xseq_HLeft_seq('<')),     
      ?Xseq_HLeft_seq_plus_payload('<'),        
      not(?Xseq_plus_payload_HLeft_seq_plus_payload('<')) ->
    ReverseOverlapppingSize = modulo32bit(HLeft#packet.seg_seq + HLeft#packet.payload_size - X#packet.seg_seq),
    Xpayload = X#packet.payload,
    <<_ReverseOverlapppingPayload:ReverseOverlapppingSize/binary, Rest/binary>> = <<Xpayload/binary>>,
    LeftNew = Left,
    RightNew = Right,
    XNew = X#packet{seg_seq = X#packet.seg_seq + ReverseOverlapppingSize, 
		    payload_size = byte_size(<<Rest/binary>>), 
		    payload = <<Rest/binary>>},
    insert(XNew, {LeftNew, RightNew}, ForwardOverlapStrategy, _Overlap, calclualte_comp(LeftNew, RightNew, XNew));

%% ForwardOverlap, not overlapping with left, but overlapping with right

insert(X, {[_HLeft|_TLeft]=Left, [HRight|_TRight]=Right}, ForwardOverlapStrategy, _Overlap, {CompL, CompR}) when 
      %%(HLeft#packet.seg_seq + HLeft#packet.payload_size =< X#packet.seg_seq) and
      %%(HRight#packet.seg_seq < X#packet.seg_seq + X#packet.payload_size) -> %% full overlapping area with right, thus replace old data
      not(?Xseq_HLeft_seq_plus_payload('<')),
      ?HRight_Xseq_plus_payload('<'),
      ?HRight_Xseq('<') ->      %% added for testing purposes
    NonOverlapppingSize = modulo32bit(HRight#packet.seg_seq - X#packet.seg_seq),
    Xpayload = X#packet.payload,
    <<NonOverlapppingPayload:NonOverlapppingSize/binary, Rest/binary>> = <<Xpayload/binary>>,
    LeftNew = [X#packet{
		     payload_size = NonOverlapppingSize, 
		     payload = <<NonOverlapppingPayload/binary>>}|Left],
    RightNew = Right,
    XNew = X#packet{ 
	     seg_seq  = X#packet.seg_seq + NonOverlapppingSize,
	     payload_size = byte_size(<<Rest/binary>>), 
	     payload = <<Rest/binary>>},
    insert(X, {LeftNew, RightNew}, ForwardOverlapStrategy, _OverlapNew = forward_overlap, calclualte_comp(LeftNew, RightNew, XNew)); %% Replace Right


%% ForwardOverlap, not overlapping with left, but overlapping with right

insert(X, {[_HLeft|_TLeft]=Left, [HRight|_TRight]=Right}, ForwardOverlapStrategy, _Overlap, {CompL, CompR}) when 
      %%(HLeft#packet.seg_seq + HLeft#packet.payload_size =< X#packet.seg_seq) and
      %%(HRight#packet.seg_seq < X#packet.seg_seq + X#packet.payload_size) -> %% full overlapping area with right, thus replace old data
      not(?Xseq_HLeft_seq_plus_payload('<')),
      ?HRight_Xseq_plus_payload('<') ->
    NonOverlapppingSize = modulo32bit(HRight#packet.seg_seq - X#packet.seg_seq),
    Xpayload = X#packet.payload,
    <<NonOverlapppingPayload:NonOverlapppingSize/binary, Rest/binary>> = <<Xpayload/binary>>,
    LeftNew = [X#packet{
		     payload_size = NonOverlapppingSize, 
		     payload = <<NonOverlapppingPayload/binary>>}|Left],
    RightNew = Right,
    XNew = X#packet{ 
	     seg_seq  = X#packet.seg_seq + NonOverlapppingSize,
	     payload_size = byte_size(<<Rest/binary>>), 
	     payload = <<Rest/binary>>},
    insert(XNew, {LeftNew, RightNew}, ForwardOverlapStrategy, _OverlapNew = forward_overlap, calclualte_comp(LeftNew, RightNew, XNew)); %% Replace Right		     
		     
%% ForwardOverlap, partial overlapping, with Strategy always_favour_old_data:

insert(X, {[HLeft|_TLeft]=Left, Right}, _ForwardOverlapStrategy = always_favour_old_data, _Overlap, {CompL, _CompR}) when 
      %%(X#packet.seg_seq == HLeft#packet.seg_seq) and
      %%(X#packet.payload_size =<  HLeft#packet.payload_size) -> %% partial overlapping area with left
      ?Xseq_HLeft_seq_plus_payload('=='),
      (X#packet.payload_size =<  HLeft#packet.payload_size) ->
    {Left, Right};

%% ForwardOverlap, full overlapping, with Strategy always_favour_old_data

insert(X, {[HLeft|_TLeft]=Left, Right}, ForwardOverlapStrategy = always_favour_old_data, _Overlap, {CompL, _CompR}) when 
      %%(X#packet.seg_seq == HLeft#packet.seg_seq) and
      %%(HLeft#packet.payload_size < X#packet.payload_size) -> %% full overlapping area with left, thus replace old data
      ?Xseq_HLeft_seq_plus_payload('=='),
      (HLeft#packet.payload_size < X#packet.payload_size) ->
    ForwardOverlapppingSize = modulo32bit(X#packet.payload_size - HLeft#packet.payload_size),
    Xpayload = X#packet.payload,
    <<_ForwardOverlapppingPayload:ForwardOverlapppingSize/binary, Rest/binary>> = <<Xpayload/binary>>,
    LeftNew = Left,
    RightNew = Right,
    XNew = X#packet{seg_seq = HLeft#packet.seg_seq+HLeft#packet.payload_size, 
		    payload_size = byte_size(<<Rest/binary>>), 
		    payload = <<Rest/binary>>},
    insert(XNew, {LeftNew, RightNew}, ForwardOverlapStrategy, _Overlap, calclualte_comp(LeftNew, RightNew, XNew));

%% ForwardOverlap, full overlapping, with Strategy always_favour_old_data

insert(X, {[_HLeft|_TLeft]=Left, [HRight|_TRight]=Right}, ForwardOverlapStrategy = always_favour_old_data, _Overlap, {CompL, CompR}) when 
      %%(HLeft#packet.seg_seq + HLeft#packet.payload_size == X#packet.seg_seq) and
      %%(HRight#packet.seg_seq =< X#packet.seg_seq) and
      %%(HRight#packet.seg_seq + HRight#packet.payload_size =< X#packet.seg_seq + X#packet.payload_size) -> %% full overlapping area with left, thus keep old data
      ?Xseq_HLeft_seq_plus_payload('=='),
      not(?HRight_Xseq('>')),
      not(?HRight_plus_payload_Xseq_plus_payload('>')) ->
    ForwardOverlapppingSize = modulo32bit(X#packet.seg_seq- (HRight#packet.seg_seq + HRight#packet.payload_size)),
      Xpayload = X#packet.payload,
    <<ForwardOverlapppingPayload:ForwardOverlapppingSize/binary, Rest/binary>> = <<Xpayload/binary>>,
    LeftNew = [X#packet{seg_seq = X#packet.seg_seq, 
		    payload_size = ForwardOverlapppingSize, 
		    payload = <<ForwardOverlapppingPayload/binary>>}|Left],
    RightNew = Right,
    XNew = X#packet{seg_seq = X#packet.seg_seq+ForwardOverlapppingSize, 
		    payload_size = byte_size(<<Rest/binary>>), 
		    payload = <<Rest/binary>>},
    insert(XNew,
	   {LeftNew, RightNew}, ForwardOverlapStrategy, _Overlap, calclualte_comp(LeftNew, RightNew, XNew));

%% ForwardOverlap, full overlapping, with Strategy always_favour_old_data

insert(X, {[HLeft|_TLeft]=Left, [_HRight|_TRight]=Right}, ForwardOverlapStrategy = always_favour_old_data, _Overlap, {CompL, CompR}) when 
      %%(HLeft#packet.seg_seq + HLeft#packet.payload_size < X#packet.seg_seq) and
      %%(HRight#packet.seg_seq < X#packet.seg_seq + X#packet.payload_size) -> %% full overlapping area with left, thus keep old data
      ?Xseq_HLeft_seq_plus_payload('>'),
      ?HRight_Xseq_plus_payload('<') ->

    ForwardOverlapppingSize = modulo32bit(X#packet.seg_seq - (HLeft#packet.seg_seq+HLeft#packet.payload_size)),
    Xpayload = X#packet.payload,
    <<_ForwardOverlapppingPayload:ForwardOverlapppingSize/binary, Rest/binary>> = <<Xpayload/binary>>,
    LeftNew = Left,
    RightNew = Right,
    XNew = X#packet{seg_seq = X#packet.seg_seq+ForwardOverlapppingSize, 
		    payload_size = byte_size(<<Rest/binary>>), 
		    payload = <<Rest/binary>>},
    insert(XNew,
	   {LeftNew, RightNew}, ForwardOverlapStrategy, _Overlap, calclualte_comp(LeftNew, RightNew, XNew));


%% ForwardOverlap, full overlapping, with Strategy favour_new_data_for_forward_overlap

insert(X, {[HLeft|TLeft]=_Left, Right}, ForwardOverlapStrategy = favour_new_data_for_forward_overlap, _Overlap, {CompL, _CompR}) when 
      %%(X#packet.seg_seq == HLeft#packet.seg_seq) and
      %%(HLeft#packet.payload_size < X#packet.payload_size) -> %% full overlapping area with left, thus replace old data
      ?Xseq_HLeft_seq('=='),
      (HLeft#packet.payload_size < X#packet.payload_size) ->
    ForwardOverlapppingSize = modulo32bit(X#packet.payload_size - HLeft#packet.payload_size),
    Xpayload = X#packet.payload,
    <<ForwardOverlapppingPayload:ForwardOverlapppingSize/binary, Rest/binary>> = <<Xpayload/binary>>,
    LeftNew = [X#packet{payload_size = ForwardOverlapppingSize, 
		      payload = <<ForwardOverlapppingPayload/binary>>}|TLeft],
    RightNew = Right,
   XNew = X#packet{seg_seq = HLeft#packet.seg_seq+HLeft#packet.payload_size, 
		    payload_size = byte_size(<<Rest/binary>>), 
		    payload = <<Rest/binary>>},
   insert(XNew,
	   {LeftNew, RightNew}, ForwardOverlapStrategy, _Overlap, calclualte_comp(LeftNew, RightNew, XNew)).
%%;

%%insert(X, {[HLeft|_TLeft]=Left, [HRight|_TRight]=Right}, ForwardOverlapStrategy) ->
%%    io:format("Called with X: ~p, Left:~p, Right:~p, ForwardOverlapStrategy:~p~n~n", [X, Left, Right, ForwardOverlapStrategy]), 
%%    io:format("Condition1:~p, Condition2: ~p",[HLeft#packet.seg_seq + HLeft#packet.payload_size =< X#packet.seg_seq,
%%					       HRight#packet.seg_seq + HRight#packet.payload_size =< X#packet.seg_seq + X#packet.payload_size]).

modulo32bit(Value) when is_integer(Value)->
    Value band 16#FFFFFFFF.

%% See RFC 1982 for Serial Number Arithmetic 
    
compare_32(I1, I2) ->
  C1 = I1 band 16#FFFFFFFF,
  C2 = I2 band 16#FFFFFFFF,
  compareMod_32(C1, C2).

compareMod_32(I1, I2) when I1 == I2 ->
    '==';

compareMod_32(I1, I2) when (I1 < I2) and ((I2 - I1) < 16#80000000) ->
    '<';

compareMod_32(I1, I2) when (I1 > I2) and ((I1 - I2) > 16#80000000) ->
    '<';

compareMod_32(I1, I2) when (I1 < I2) and ((I2 - I1) > 16#80000000) ->
    '>';

compareMod_32(I1, I2) when (I1 > I2) and ((I1 - I2) < 16#80000000) ->
    '>';

compareMod_32(_I1, _I2) ->
    undef.
