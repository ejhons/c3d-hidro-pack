// secao.dcl - dialogo do visualizador de secoes de sarjeta (plugins/secao.lsp)
// Somente ASCII, de proposito (sem problemas de codificacao).

secao_dialog : dialog {
  label = "HYDRO - Secoes de Sarjeta";

  : row {

    : boxed_column {
      label = "Secoes cadastradas";
      : list_box {
        key = "lst";
        width = 30;
        height = 24;
        allow_accept = true;
      }
    }

    : column {

      : boxed_column {
        label = "Secao transversal";
        : image {
          key = "img";
          width = 76;
          height = 18;
          color = -2;
        }
        : text { key = "t_esc"; width = 74; }
      }

      : row {
        : boxed_radio_row {
          label = "Exagero vertical";
          : radio_button { key = "ex1";  label = "1x (real)"; }
          : radio_button { key = "ex2";  label = "2x"; }
          : radio_button { key = "ex5";  label = "5x"; }
          : radio_button { key = "ex10"; label = "10x"; }
        }
        : boxed_column {
          label = "Escala";
          : toggle { key = "comum"; label = "&Comum a todas as secoes"; }
        }
      }

      : boxed_row {
        label = "Escoamento (Izzard)";
        : edit_box { key = "q";  label = "&Q (m3/s):";      edit_width = 9; }
        : edit_box { key = "sl"; label = "&S long. (m/m):"; edit_width = 9; }
        : button {
          key = "ultimo";
          label = "&Ultimo calculo";
          width = 16;
          fixed_width = true;
        }
      }

      : boxed_column {
        label = "Parametros e resultado";
        : text { key = "t_par";   width = 74; }
        : text { key = "t_r";     width = 74; }
        : text { key = "t_res1";  width = 74; }
        : text { key = "t_res2";  width = 74; }
        : text { key = "t_aviso"; width = 74; }
      }

    }
  }

  spacer;

  : row {
    alignment = centered;
    : button {
      key = "accept";
      label = "&Selecionar";
      is_default = true;
      width = 14;
      fixed_width = true;
    }
    : button {
      key = "inserir";
      label = "&Inserir no desenho";
      width = 20;
      fixed_width = true;
    }
    : button {
      key = "cancel";
      label = "Fechar";
      is_cancel = true;
      width = 14;
      fixed_width = true;
    }
  }
}
