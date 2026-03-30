{ config, pkgs, lib, ... }:

# ============================================================
# Python 统一环境模块
#
# 提供系统级共享 Python 环境，供所有 AI/Web 服务使用
# 避免每个服务单独 nix-shell 造成的重复下载和启动延迟
# ============================================================

let
  sharedPythonEnv = pkgs.python313.withPackages (ps: with ps; [
    # Web 框架
    fastapi
    uvicorn
    flask
    sse-starlette
    python-multipart
    websockets
    aiofiles

    # HTTP 客户端
    requests
    httpx

    # 数据验证
    pydantic

    # 文档解析
    pypdf
    python-docx
    openpyxl

    # AI SDK
    anthropic
  ]);
in
{
  options.charlie.sharedPythonEnv = lib.mkOption {
    type = lib.types.package;
    default = sharedPythonEnv;
    readOnly = true;
    description = "Shared Python 3.13 environment for all services";
  };

  config = {
    environment.systemPackages = [ sharedPythonEnv ];
  };
}
