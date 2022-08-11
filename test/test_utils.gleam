type IoFormat {
  User
}

external fn io_fwrite(format: IoFormat, output_format: String, data: any) -> Nil =
  "io" "fwrite"

pub fn io_fwrite_user(data: anything) {
  io_fwrite(User, "~tp\n", [data])
}
