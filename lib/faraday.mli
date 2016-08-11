(** Serialization primitives built for speed an memory-efficiency. *)

type bigstring =
  (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

type t
(** The type of a serializer. *)


(** {2 Constructors} *)

val create : int -> t
(** [create len] creates a serializer with a fixed-length internal buffer of
    length [len]. *)

val of_bigstring : bigstring -> t
(** [of_bigstring buf] creates a serializer, using [buf] as its internal
    buffer. The serializer takes ownership of [buf] until the serializer has
    been closed and flushed of all output. *)


(** {2 Buffered Writes}

    Serializers manage an internal buffer for batching small writes. The size
    of this buffer is determined when the serializer is created and does not
    change throughout the lifetime of that serializer. If the buffer does not
    contain sufficient space to service the buffered writes of the caller, it
    will cease to batch writes and begin to allocate. See the documentation for
    {!free_bytes_to_write} for additional details. *)

val write_string : t -> ?off:int -> ?len:int -> string -> unit
(** [write_string t ?off ?len str] copies [str] into the serializer's
    internal write buffer. The contents of [str] will be batched with prior or
    subsequent writes, if possible. *)

val write_bytes : t -> ?off:int -> ?len:int -> Bytes.t -> unit
(** [write_bytes t ?off ?len bytes] copies [bytes] into the serializer's
    internal write buffer. The contents of [bytes] will be batched with prior
    or subsequent writes, if possible. *)

val write_char : t -> char -> unit
(** [write_char t char] copies [char] into the serializer's internal buffer.
    [char] will be batched with prior or subsequent writes, if possible. *)


(** {2 Unbuffered Writes} *)

val schedule_string : t -> ?off:int -> ?len:int -> string -> unit
(** [schedule_string t ?off ?len str] schedules [str] to be written the next
    time the serializer surfaces writes to the user. [str] is not copied in
    this process. *)

val schedule_bytes
  :   t
  -> ?free:(Bytes.t -> unit)
  -> ?off:int
  -> ?len:int
  -> Bytes.t
  -> unit
  (** [schedule_bytes t ?free ?off ?len bytes] schedules [bytes] to be written
      the next time the serializer surfaces writes to the user. [bytes] is not
      copied in this process, so [bytes] should only be modified after the
      [free] function has been called on [bytes], if provided. *)

val schedule_bigstring
  :  t
  -> ?free:(bigstring -> unit)
  -> ?off:int
  -> ?len:int
  -> bigstring
  -> unit
  (** [schedule_bigstring t ?free ?off ?len bigstring] schedules [bigstring] to
      be written the next time the serializer surfaces writes to the user.
      [bigstring] is not copied in this process, so [bigstring] should only be
      modified after the [free] function has been called on [bigstring], if
      provided. *)


(** {2 Control Operations} *)

val yield : t -> unit
(** [yield t] causes the serializer to delay surfacing writes to the user,
    instead returning a {!Yield} operation with an associated continuation [k].
    This gives the serializer an opportunity to collect additional writes
    before sending them to the underlying device, which will increase the write
    batch size. Barring any intervening calls to [yield t], calling the
    continuation [k] will surface writes to the user. *)

val close : t -> unit
(** [close t] closes the serializer. All subsequent write calls will raise, and
    any pending or subsequent {yield} calls will be ignored. If the serializer
    has any pending writes, user code will have an opportunity to service them
    before it receives the {Close} operation. *)

val free_bytes_to_write : t -> int
(** [free_bytes_to_write t] returns the free space, in bytes, of the
    serializer's write buffer. If a call to {!write_bytes} or {!write_char} has
    a length that exceeds the serializer's free size, the serializer will
    allocate an additional buffer, copy the contents of the write call into
    that buffer, and schedule it as a separate {!iovec}. If a call to
    {!write_string} has a length that exceeds the serializer's free size, the
    serializer will schedule it as {!iovec}. *)


(** {2 Running} *)

type buffer =
  [ `String    of string
  | `Bytes     of Bytes.t
  | `Bigstring of bigstring ]

type 'a iovec =
  { buffer : 'a
  ; off : int
  ; len : int }
(** A view into {buffer} starting at {off} and with length {len}. *)

type op =
  | Writev of buffer iovec list * (int  -> op)
    (** Write the {iovec}s, passing the continuation the number of bytes
        successfully written. *)
  | Yield  of                     (unit -> op)
    (** Yield to other threads of control, whether logical or actual, and wait
        for additional output before procedding. The method for achieving this
        is application-specific. It is safe to call the continuation even no
        additional output has been received. *)
  | Close
    (** Serialization is complete. No further output will be received. *)

val serialize : t -> op
(** [serialize t] runs [t], surfacing operations to the user, together with an
    explicit continuation, as they become available. The continuation of the
    {Writev} operation takes the number of bytes that were successfuly written
    from the list of {iovec}s. When to call the continuations in the {Writev}
    and {Yield} case are application-specific. *)

val serialize_to_string : t -> string
(** [serialize_to_string t] runs [t], collecting the output into a string and
    returning it. [t] is immediately closed, and all calls to {yield} are
    ignored. *)