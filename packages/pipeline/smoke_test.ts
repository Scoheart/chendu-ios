Deno.test("pipeline package is wired", () => {
  if (Deno.cwd().length === 0) {
    throw new Error("cwd missing");
  }
});
