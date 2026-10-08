// hidrograma.dcl - dialogo do visualizador de hidrogramas (plugins/hidrograma.lsp)
// Somente ASCII, de proposito (sem problemas de codificacao).

hidro_dialog : dialog {
  label = "HYDRO - Hidrogramas da Bacia";

  : row {

    : boxed_column {
      label = "Hidrogramas (Ctrl para varios)";
      : list_box {
        key = "lst";
        width = 40;
        height = 26;
        multiple_select = true;
      }
    }

    : column {

      : boxed_column {
        label = "Hidrograma";
        : image {
          key = "img";
          width = 72;
          height = 15;
          color = -2;
        }
        : text { key = "t_eixos"; width = 70; }
      }

      : boxed_column {
        label = "Selecionados (cor no grafico)";
        : list_box {
          key = "info";
          width = 70;
          height = 4;
        }
      }

      : boxed_column {
        label = "Tabela do primeiro selecionado";
        : list_box {
          key = "tab";
          width = 70;
          height = 9;
          fixed_width_font = true;
          tabs = "14 32";
        }
      }

    }
  }

  spacer;

  : row {
    alignment = centered;
    : button {
      key = "csv";
      label = "Exportar &CSV";
      width = 16;
      fixed_width = true;
    }
    : button {
      key = "excluir";
      label = "&Excluir";
      width = 12;
      fixed_width = true;
    }
    : button {
      key = "cancel";
      label = "Fechar";
      is_cancel = true;
      is_default = true;
      width = 12;
      fixed_width = true;
    }
  }
}
