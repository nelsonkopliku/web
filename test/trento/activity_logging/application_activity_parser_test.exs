# SPDX-FileCopyrightText: SUSE LLC
# SPDX-License-Identifier: GPL-3.0-or-later

defmodule Trento.ActivityLog.ApplicationActivityParserTest do
  use ExUnit.Case, async: true

  alias Trento.ActivityLog.Logger.Parser.ApplicationActivityParser

  test "should take the actor given by the application, the system otherwise" do
    assert "admin" ==
             ApplicationActivityParser.get_activity_actor(:operation_scheduled, %{actor: "admin"})

    assert "system" == ApplicationActivityParser.get_activity_actor(:operation_scheduled, %{})
  end

  test "should take the metadata given by the application" do
    assert %{foo: "bar"} ==
             ApplicationActivityParser.get_activity_metadata(:operation_scheduled, %{
               metadata: %{foo: "bar"}
             })

    assert %{} == ApplicationActivityParser.get_activity_metadata(:operation_scheduled, %{})
  end
end
