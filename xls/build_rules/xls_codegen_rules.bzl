# Copyright 2021 The XLS Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
This module contains codegen-related build rules for XLS.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("//xls/build_rules:xls_providers.bzl", "CodegenInfo")
load("//xls/build_rules:xls_ir_rules.bzl", "xls_ir_common_attrs")

_DEFAULT_CODEGEN_TARGET = "//xls/tools:codegen_main"

xls_ir_verilog_attrs = {
    "codegen_args": attr.string_dict(
        doc = "Arguments of the codegen tool.",
    ),
    "verilog_file": attr.output(
        doc = "The Verilog file generated.",
    ),
    "module_sig_file": attr.output(
        doc = "The module signature of the generated Verilog file.",
    ),
    "schedule_file": attr.output(
        doc = "The schedule of the generated Verilog file.",
    ),
    "_codegen_tool": attr.label(
        doc = "The target of the codegen executable.",
        default = Label(_DEFAULT_CODEGEN_TARGET),
        allow_single_file = True,
        executable = True,
        cfg = "exec",
    ),
}

def xls_ir_verilog_impl(ctx, src):
    """The core implementation of the 'xls_ir_verilog' rule.

    Generates a Verilog file, module signature file and schedule file.

    Args:
      ctx: The current rule's context object.
      src: The source file.
    Returns:
      CodegenInfo provider
      DefaultInfo provider
    """
    my_generated_files = []

    # default arguments
    codegen_args = ctx.attr.codegen_args
    codegen_flags = " --delay_model=" + codegen_args.get("delay_model", "unit")

    # parse arguments
    CODEGEN_FLAGS = (
        "clock_period_ps",
        "pipeline_stages",
        "delay_model",
        "entry",
        "generator",
        "input_valid_signal",
        "output_valid_signal",
        "manual_load_enable_signal",
        "flop_inputs",
        "flop_outputs",
        "module_name",
        "clock_margin_percent",
        "reset",
        "reset_active_low",
        "reset_asynchronous",
        "use_system_verilog",
    )
    verilog_file = None
    module_sig_file = None
    schedule_file = None
    uses_combinational_generator = False
    for flag_name in codegen_args:
        if flag_name in CODEGEN_FLAGS:
            codegen_flags += (
                " --{}={}".format(flag_name, codegen_args[flag_name])
            )
            if (
                flag_name == "generator" and
                codegen_args[flag_name] == "combinational"
            ):
                uses_combinational_generator = True
        else:
            fail("Unrecognized argument: %s." % flag_name)

    if not uses_combinational_generator:
        # Pipeline generator produces a schedule artifact.
        schedule_file = ctx.actions.declare_file(
            ctx.attr.name + ".schedule.textproto",
        )
        my_generated_files.append(schedule_file)
        codegen_flags += (
            " --output_schedule_path={}".format(schedule_file.path)
        )
    verilog_file = ctx.actions.declare_file(ctx.attr.name + ".v")
    module_sig_file = ctx.actions.declare_file(ctx.attr.name + ".sig.textproto")
    my_generated_files += [verilog_file, module_sig_file]
    codegen_flags += " --output_verilog_path={}".format(verilog_file.path)
    codegen_flags += " --output_signature_path={}".format(module_sig_file.path)

    ctx.actions.run_shell(
        outputs = my_generated_files,
        tools = [ctx.executable._codegen_tool],
        inputs = [src, ctx.executable._codegen_tool],
        command = "{} {} {}".format(
            ctx.executable._codegen_tool.path,
            src.path,
            codegen_flags,
        ),
        mnemonic = "Codegen",
        progress_message = "Building Verilog file: %s" % (verilog_file.path),
    )
    return [
        CodegenInfo(
            verilog_file = verilog_file,
            module_sig_file = module_sig_file,
            schedule_file = schedule_file,
        ),
        DefaultInfo(
            files = depset(my_generated_files),
        ),
    ]

def _xls_ir_verilog_impl_wrapper(ctx):
    """The implementation of the 'xls_ir_verilog' rule.

    Wrapper for xls_ir_verilog_impl. See: xls_ir_verilog_impl.

    Args:
      ctx: The current rule's context object.
    Returns:
      See: codegen_impl.
    """
    return xls_ir_verilog_impl(ctx, ctx.file.src)

xls_ir_verilog = rule(
    doc = """A build rule that generates a Verilog file.

        Examples:

        1) A file as the source.

        ```
            xls_ir_verilog(
                name = "a_verilog",
                src = "a.ir",
            )
        ```

        2) A target as the source.

        ```
            xls_ir_opt_ir(
                name = "a_opt_ir",
                src = "a.ir",
            )

            xls_ir_verilog(
                name = "a_verilog",
                src = ":a_opt_ir",
            )
        ```
    """,
    implementation = _xls_ir_verilog_impl_wrapper,
    attrs = dicts.add(
        xls_ir_common_attrs,
        xls_ir_verilog_attrs,
    ),
)
