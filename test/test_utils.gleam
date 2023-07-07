type IoFormat {
  User
}

@external(erlang, "io", "fwrite")
fn io_fwrite(format: IoFormat, output_format: String, data: any) -> Nil

pub fn io_fwrite_user(data: anything) {
  io_fwrite(User, "~tp\n", [data])
}
